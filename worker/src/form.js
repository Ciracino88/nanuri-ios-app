// 카카오톡 인앱 브라우저에서 열리는 청구 폼.

// 앱의 Profile.swift koreanBanks와 반드시 같아야 한다.
// 토스 송금 딥링크(supertoss://send?bank=...)가 이 문자열을 그대로 쓴다.
const BANKS = [
    '국민은행', '신한은행', '우리은행', '하나은행',
    '카카오뱅크', '토스뱅크', 'IBK기업은행', 'NH농협은행',
    'SC제일은행', '케이뱅크', '새마을금고', '신협', '우체국',
];

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

const STYLE = `
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
    margin: 0; padding: 24px 20px 40px;
    font-family: -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', sans-serif;
    background: #f2f2f7; color: #111;
}
h1 { font-size: 20px; margin: 0 0 4px; }
.sub { font-size: 13px; color: #666; margin: 0 0 24px; }
label { display: block; font-size: 13px; font-weight: 600; margin: 18px 0 6px; }
input, select, textarea {
    width: 100%; padding: 13px 14px; font-size: 16px;
    border: 1px solid #d8d8dd; border-radius: 12px;
    background: #fff; color: inherit; font-family: inherit;
}
textarea { resize: vertical; min-height: 72px; }
input:focus, select:focus, textarea:focus { outline: 2px solid #3478f6; outline-offset: -1px; }
.hint { font-size: 12px; color: #888; margin-top: 6px; }
button {
    width: 100%; margin-top: 28px; padding: 16px;
    font-size: 16px; font-weight: 600; font-family: inherit;
    border: 0; border-radius: 14px; background: #3478f6; color: #fff;
}
button:disabled { opacity: .5; }
.error {
    display: none; margin-top: 16px; padding: 12px 14px;
    background: #ffe9e9; color: #c22; border-radius: 10px; font-size: 13px;
}
.done { text-align: center; padding: 64px 24px; }
.done .mark { font-size: 48px; }
.done h1 { margin-top: 16px; }
@media (prefers-color-scheme: dark) {
    body { background: #000; color: #f2f2f7; }
    input, select, textarea { background: #1c1c1e; border-color: #38383a; }
    .sub, .hint { color: #98989f; }
    .error { background: #3a1f1f; color: #ff9b9b; }
}
`;

/** 청구 폼 페이지. prefill은 같은 발신자의 직전 청구서 값이다. */
export function renderForm(token, prefill = {}) {
    const options = BANKS
        .map((bank) => `<option${bank === prefill.bank_name ? ' selected' : ''}>${bank}</option>`)
        .join('');

    return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>청구서 작성</title>
<style>${STYLE}</style>
</head>
<body>
<h1>청구서 작성</h1>
<p class="sub">작성해 주시면 담당자에게 바로 전달됩니다.</p>

<form id="f" method="post" action="/bill/submit" enctype="multipart/form-data">
    <input type="hidden" name="token" value="${escapeHtml(token)}">

    <label for="submitter_name">이름</label>
    <input id="submitter_name" name="submitter_name" required maxlength="30"
           value="${escapeHtml(prefill.submitter_name)}">

    <label for="bank_name">은행</label>
    <select id="bank_name" name="bank_name" required>
        <option value="">선택해 주세요</option>
        ${options}
    </select>

    <label for="account_number">계좌번호</label>
    <input id="account_number" name="account_number" required inputmode="numeric"
           maxlength="30" value="${escapeHtml(prefill.account_number)}">
    <p class="hint">'-' 는 있어도 없어도 괜찮아요.</p>

    <label for="title">청구 항목</label>
    <input id="title" name="title" required maxlength="60" placeholder="예) 청년부 간식 구입">

    <label for="amount">금액 (원)</label>
    <input id="amount" name="amount" required inputmode="numeric" placeholder="예) 32000">

    <label for="receipt">영수증 사진</label>
    <input id="receipt" name="receipt" type="file" accept="image/*">
    <p class="hint">없으면 비워두셔도 됩니다.</p>

    <label for="note">비고</label>
    <textarea id="note" name="note" maxlength="300" placeholder="남길 말이 있으면 적어주세요"></textarea>

    <button type="submit">제출하기</button>
    <p class="error" id="err"></p>
</form>

<script>
const form = document.getElementById('f');
const button = form.querySelector('button');
const error = document.getElementById('err');

form.addEventListener('submit', async (event) => {
    event.preventDefault();
    error.style.display = 'none';
    button.disabled = true;
    button.textContent = '제출 중...';

    try {
        const response = await fetch('/bill/submit', { method: 'POST', body: new FormData(form) });
        const result = await response.json();
        if (!response.ok) throw new Error(result.message || '제출에 실패했어요.');
        document.body.innerHTML =
            '<div class="done"><div class="mark">\\u2705</div><h1>접수됐어요</h1>' +
            '<p class="sub">확인 후 송금해 드릴게요.<br>이 창은 닫으셔도 됩니다.</p></div>';
    } catch (e) {
        error.textContent = e.message;
        error.style.display = 'block';
        button.disabled = false;
        button.textContent = '제출하기';
    }
});
</script>
</body>
</html>`;
}

/** 토큰이 만료됐거나 잘못된 경로로 들어온 경우. */
export function renderExpired() {
    return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>링크 만료</title>
<style>${STYLE}</style>
</head>
<body>
<div class="done">
    <div class="mark">⏰</div>
    <h1>링크가 만료됐어요</h1>
    <p class="sub">채팅방에서 [청구하기]를 다시 눌러주세요.</p>
</div>
</body>
</html>`;
}
