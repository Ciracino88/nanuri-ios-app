import "@supabase/functions-js/edge-runtime.d.ts";

const TOSS_SENDER = "no.reply@mail.tossbank.com";

interface BankTransaction {
  datetime: string;
  type: string;
  amount: number;
  balance: number;
  description: string;
}

async function getGmailMessages(accessToken: string): Promise<string[]> {
  const query = encodeURIComponent(`from:${TOSS_SENDER} has:attachment filename:pdf`);
  const res = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages?q=${query}&maxResults=10`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  const data = await res.json();
  console.log("Gmail 검색 결과:", JSON.stringify(data));
  return (data.messages ?? []).map((m: { id: string }) => m.id);
}

async function getPdfAttachment(accessToken: string, messageId: string): Promise<Uint8Array | null> {
  const res = await fetch(
    `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}`,
    { headers: { Authorization: `Bearer ${accessToken}` } }
  );
  const msg = await res.json();

  const findPdfPart = (parts: any[]): any => {
    for (const part of parts) {
      if (part.mimeType === "application/pdf" && part.filename?.endsWith(".pdf")) return part;
      if (part.parts) {
        const found = findPdfPart(part.parts);
        if (found) return found;
      }
    }
    return null;
  };

  const allParts = msg.payload?.parts ?? [];
  console.log("첨부파일 parts:", JSON.stringify(allParts.map((p: any) => ({ filename: p.filename, mimeType: p.mimeType }))));

  const pdfPart = findPdfPart(allParts);
  if (!pdfPart) return null;

  let base64: string;
  if (pdfPart.body?.data) {
    base64 = pdfPart.body.data;
  } else if (pdfPart.body?.attachmentId) {
    const attRes = await fetch(
      `https://gmail.googleapis.com/gmail/v1/users/me/messages/${messageId}/attachments/${pdfPart.body.attachmentId}`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );
    const att = await attRes.json();
    base64 = att.data;
  } else {
    return null;
  }

  base64 = base64.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

async function extractTextFromPdf(pdfData: Uint8Array): Promise<string> {
  const { getDocument } = await import("npm:pdfjs-dist@4.4.168/legacy/build/pdf.mjs");
  const doc = await getDocument({ data: pdfData }).promise;
  let fullText = "";
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    const pageText = content.items.map((item: any) => item.str).join(" ");
    fullText += pageText + "\n";
  }
  return fullText;
}

function parsePdfText(text: string): BankTransaction[] {
  const datePattern = /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/g;
  const lines = text.split("\n").map(l => l.trim()).filter(Boolean);
  const fullText = lines.join(" ");

  const rowPattern = /(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(입금|출금|이자입금|ATM입금|ATM출금|자동이체|이체)\s+([-\d,]+)\s+([\d,]+)\s+(.+?)(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}|발급일자|$)/g;

  const transactions: BankTransaction[] = [];
  let match;
  while ((match = rowPattern.exec(fullText)) !== null) {
    const description = match[5].trim().replace(/\s+/g, " ");
    transactions.push({
      datetime: match[1],
      type: match[2],
      amount: parseInt(match[3].replace(/,/g, "")),
      balance: parseInt(match[4].replace(/,/g, "")),
      description,
    });
  }
  return transactions;
}

export default {
  fetch: async (req: Request) => {
    if (req.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        },
      });
    }

    try {
      const { accessToken, messageIndex = 0 } = await req.json();
      if (!accessToken) {
        return Response.json({ error: "accessToken required" }, { status: 400 });
      }

      const messageIds = await getGmailMessages(accessToken);
      if (messageIds.length === 0) {
        return Response.json({ error: "토스뱅크 거래내역 메일을 찾을 수 없습니다." }, { status: 404 });
      }

      const targetId = messageIds[messageIndex];
      const pdfData = await getPdfAttachment(accessToken, targetId);
      if (!pdfData) {
        return Response.json({ error: "PDF 첨부파일을 찾을 수 없습니다." }, { status: 404 });
      }

      const text = await extractTextFromPdf(pdfData);
      console.log("추출된 텍스트 앞부분:", text.substring(0, 300));

      const transactions = parsePdfText(text);
      console.log("파싱된 거래내역 수:", transactions.length);

      return Response.json({
        total: messageIds.length,
        messageId: targetId,
        transactions,
      }, {
        headers: { "Access-Control-Allow-Origin": "*" },
      });
    } catch (e) {
      console.error("에러:", e);
      return Response.json({ error: String(e) }, { status: 500 });
    }
  },
};
