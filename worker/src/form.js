// 공개 청구 폼.
//
// 받는 값은 네 가지뿐이다 — 이름, 청구 항목, 금액, 영수증 사진.
// 은행·계좌는 받지 않는다. 관리자가 앱의 계좌부에 이름↔계좌를 등록해 두고,
// 들어온 이름으로 대조해서 송금한다.

const STYLE = `
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
    margin: 0; padding: 24px 20px 40px;
    font-family: -apple-system, BlinkMacSystemFont, 'Apple SD Gothic Neo', sans-serif;
    background: #f2f2f7; color: #111;
}
main { max-width: 480px; margin: 0 auto; }
h1 { font-size: 20px; margin: 0 0 24px; }
.sub { font-size: 13px; color: #666; margin: 0 0 24px; }
label { display: block; font-size: 13px; font-weight: 600; margin: 18px 0 6px; }
input, textarea {
    width: 100%; padding: 13px 14px; font-size: 16px;
    border: 1px solid #d8d8dd; border-radius: 12px;
    background: #fff; color: inherit; font-family: inherit;
}
input:focus, textarea:focus { outline: 2px solid #3478f6; outline-offset: -1px; }
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
.done h1 { margin: 16px 0 4px; }
@media (prefers-color-scheme: dark) {
    body { background: #000; color: #f2f2f7; }
    input, textarea { background: #1c1c1e; border-color: #38383a; }
    .sub { color: #98989f; }
    .error { background: #3a1f1f; color: #ff9b9b; }
}
`;

export function renderForm() {
    return `<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<title>청구서 작성</title>
<style>${STYLE}</style>
</head>
<body>
<main>
<h1>청구서 작성</h1>

<form id="f" method="post" action="/bill/submit" enctype="multipart/form-data">
    <label for="submitter_name">이름</label>
    <input id="submitter_name" name="submitter_name" required maxlength="30"
           autocomplete="name" placeholder="이름을 입력해주세요">

    <label for="title">청구 항목</label>
    <input id="title" name="title" required maxlength="60" placeholder="청구 항목을 입력해주세요">

    <label for="amount">금액 (원)</label>
    <input id="amount" name="amount" required inputmode="numeric" placeholder="금액을 입력해주세요">

    <label for="receipt">영수증 사진</label>
    <input id="receipt" name="receipt" type="file" accept="image/*" required>

    <button type="submit">제출하기</button>
    <p class="error" id="err"></p>
</form>
</main>

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
