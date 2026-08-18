// 공개 청구 폼.
//
// 받는 값은 네 가지뿐이다 — 이름, 청구 항목, 금액, 영수증 사진.
// 은행·계좌는 받지 않는다. 관리자가 앱의 계좌부에 이름↔계좌를 등록해 두고,
// 들어온 이름으로 대조해서 송금한다.
//
// 사진은 고르는 즉시 브라우저에서 축소해 /bill/receipt 로 미리 올려둔다.
// 제출 버튼을 누른 뒤에 원본을 올리면 폰 업링크 때문에 십수 초씩 걸린다.
// 미리 올려두면 제출은 URL 한 줄만 보내면 되므로 사실상 즉시 끝난다.
// 이 경로가 실패해도 파일을 그대로 붙여 예전 경로로 보내니 접수는 되게 되어 있다.
//
// 미리 올렸는데 접수까지 가지 않은 사진은 R2에 남는다. 사진을 다른 걸로 바꿨을 때와
// 접수 전에 창을 닫을 때 /bill/receipt/discard 로 지운다.

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
    display: flex; align-items: center; justify-content: center; gap: 8px;
}
button:disabled { opacity: .55; }
.error {
    display: none; margin-top: 16px; padding: 12px 14px;
    background: #ffe9e9; color: #c22; border-radius: 10px; font-size: 13px;
}

/* 사진 선택 — 파일 입력을 투명하게 덮어씌운다.
   display:none 으로 숨기면 required 검사에 걸렸을 때 브라우저가 포커스를 못 준다. */
.picker {
    position: relative; display: flex; align-items: center; gap: 12px;
    padding: 14px; border: 1px dashed #c6c6cc; border-radius: 12px; background: #fff;
    min-height: 74px;
}
.picker input[type=file] {
    position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0;
    padding: 0; border: 0; border-radius: 12px;
}
.picker input[type=file]:focus-visible { outline: 2px solid #3478f6; }
.picker.filled { border-style: solid; border-color: #3478f6; }
.picker .thumb {
    width: 46px; height: 46px; flex: none; border-radius: 8px;
    object-fit: cover; background: #e9e9ee;
}
.picker .lines { min-width: 0; }
.picker .name {
    display: block; font-size: 15px; font-weight: 500;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.picker .hint { display: block; margin-top: 3px; font-size: 12px; color: #666; }
.picker .hint.warn { color: #c98a00; }

.bar { height: 3px; margin-top: 8px; border-radius: 2px; background: #e2e2e8; overflow: hidden; }
.bar i { display: block; height: 100%; width: 0; background: #3478f6; transition: width .18s ease-out; }

.spinner {
    width: 16px; height: 16px; flex: none; border-radius: 50%;
    border: 2px solid rgba(255,255,255,.35); border-top-color: #fff;
    animation: spin .7s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.status {
    margin: 10px 0 0; min-height: 17px;
    font-size: 13px; color: #666; text-align: center;
}

.done { text-align: center; padding: 56px 24px 24px; }
.done .mark { font-size: 48px; }
.done h1 { margin: 16px 0 4px; }
.done .summary {
    margin: 0 0 24px; padding: 14px; border-radius: 12px;
    background: #fff; font-size: 14px; line-height: 1.5;
}
.done button { margin-top: 0; }
.done .secondary { margin-top: 10px; background: none; color: #3478f6; }

[hidden] { display: none !important; }

@media (prefers-reduced-motion: reduce) {
    .spinner { animation-duration: 2.4s; }
    .bar i { transition: none; }
}
@media (prefers-color-scheme: dark) {
    body { background: #000; color: #f2f2f7; }
    input, textarea { background: #1c1c1e; border-color: #38383a; }
    .sub, .picker .hint, .status { color: #98989f; }
    .error { background: #3a1f1f; color: #ff9b9b; }
    .picker { background: #1c1c1e; border-color: #48484a; }
    .picker .thumb { background: #2c2c2e; }
    .bar { background: #2c2c2e; }
    .done .summary { background: #1c1c1e; }
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

<section id="form-view">
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
    <div class="picker" id="picker">
        <input id="receipt" name="receipt" type="file" accept="image/*" required>
        <img class="thumb" id="thumb" alt="" hidden>
        <span class="lines">
            <span class="name" id="picker-name">사진 첨부하기</span>
            <span class="hint" id="picker-hint">탭해서 영수증 사진을 고르세요</span>
        </span>
    </div>
    <div class="bar" id="bar" hidden><i id="bar-fill"></i></div>

    <button type="submit" id="submit">
        <span class="spinner" id="spinner" hidden></span>
        <span id="submit-label">제출하기</span>
    </button>
    <p class="status" id="status"></p>
    <p class="error" id="err"></p>
</form>
</section>

<section id="done-view" class="done" hidden>
    <div class="mark">✅</div>
    <h1>접수됐어요</h1>
    <p class="sub">확인 후 송금해 드릴게요.</p>
    <p class="summary" id="done-summary"></p>
    <button type="button" id="again">청구서 하나 더 작성하기</button>
    <button type="button" class="secondary" id="close">이 창 닫기</button>
</section>

</main>

<script>
(function () {
    'use strict';

    // 긴 변 1600px / JPEG 0.8 이면 영수증 글자는 그대로 읽히면서 3MB 사진이 300KB 안팎이 된다.
    var MAX_EDGE = 1600;
    var JPEG_QUALITY = 0.8;

    var form = document.getElementById('f');
    var fileInput = document.getElementById('receipt');
    var picker = document.getElementById('picker');
    var pickerName = document.getElementById('picker-name');
    var pickerHint = document.getElementById('picker-hint');
    var thumb = document.getElementById('thumb');
    var bar = document.getElementById('bar');
    var barFill = document.getElementById('bar-fill');
    var submitButton = document.getElementById('submit');
    var submitLabel = document.getElementById('submit-label');
    var spinner = document.getElementById('spinner');
    var statusLine = document.getElementById('status');
    var errorBox = document.getElementById('err');
    var formView = document.getElementById('form-view');
    var doneView = document.getElementById('done-view');

    // 지금 고른 사진의 준비 상태. { name, blob, ready } — ready 는 {url, token} 로 풀리는 Promise
    var receipt = null;

    function setBusy(busy, label) {
        submitButton.disabled = busy;
        spinner.hidden = !busy;
        submitLabel.textContent = busy ? label : '제출하기';
    }

    function setStatus(text) {
        statusLine.textContent = text || '';
    }

    function setProgress(ratio) {
        bar.hidden = false;
        barFill.style.width = Math.round(Math.max(0, Math.min(1, ratio)) * 100) + '%';
    }

    function showError(message) {
        errorBox.textContent = message;
        errorBox.style.display = 'block';
    }

    function formatSize(bytes) {
        return bytes >= 1024 * 1024
            ? (bytes / 1024 / 1024).toFixed(1) + 'MB'
            : Math.max(1, Math.round(bytes / 1024)) + 'KB';
    }

    function formatWon(amount) {
        return Number(amount).toLocaleString('ko-KR') + '원';
    }

    // 사진을 캔버스로 다시 그려 축소한다. 못 하면 원본을 그대로 쓴다.
    // HEIC 처럼 앱에서 못 보는 형식도 여기서 JPEG 로 바뀐다.
    function shrink(file) {
        return new Promise(function (resolve) {
            if (!window.URL || !window.URL.createObjectURL) return resolve(file);

            var objectUrl = URL.createObjectURL(file);
            var image = new Image();

            image.onload = function () {
                try {
                    var scale = Math.min(1, MAX_EDGE / Math.max(image.naturalWidth, image.naturalHeight));
                    var width = Math.max(1, Math.round(image.naturalWidth * scale));
                    var height = Math.max(1, Math.round(image.naturalHeight * scale));

                    var canvas = document.createElement('canvas');
                    canvas.width = width;
                    canvas.height = height;
                    canvas.getContext('2d').drawImage(image, 0, 0, width, height);

                    canvas.toBlob(function (blob) {
                        URL.revokeObjectURL(objectUrl);
                        // 원본이 이미 더 작은 JPEG/PNG 면 그대로 둔다.
                        var keepOriginal = !blob
                            || (blob.size >= file.size && /image\\/(jpe?g|png)/i.test(file.type));
                        resolve(keepOriginal ? file : blob);
                    }, 'image/jpeg', JPEG_QUALITY);
                } catch (e) {
                    URL.revokeObjectURL(objectUrl);
                    resolve(file);
                }
            };

            image.onerror = function () {
                URL.revokeObjectURL(objectUrl);
                resolve(file);
            };

            image.src = objectUrl;
        });
    }

    // 업로드 진행률을 보여주려고 fetch 대신 XHR 을 쓴다 (fetch 는 업로드 진행률을 안 준다).
    function upload(blob, filename) {
        return new Promise(function (resolve, reject) {
            var body = new FormData();
            body.append('receipt', blob, filename);

            var xhr = new XMLHttpRequest();
            xhr.open('POST', '/bill/receipt');
            xhr.upload.onprogress = function (event) {
                if (event.lengthComputable) setProgress(event.loaded / event.total);
            };
            xhr.onload = function () {
                var result = {};
                try { result = JSON.parse(xhr.responseText); } catch (e) { /* 무시 */ }
                if (xhr.status >= 200 && xhr.status < 300 && result.url) resolve(result);
                else reject(new Error(result.message || '사진을 올리지 못했어요.'));
            };
            xhr.onerror = function () { reject(new Error('사진을 올리지 못했어요.')); };
            xhr.send(body);
        });
    }

    // 접수에 쓰이지 않은 선행 업로드를 지운다. 창이 닫히는 중에도 나가야 해서 sendBeacon 을 쓴다.
    // (아직 올라가는 중인 사진은 result 가 없어서 대상이 아니다 — 그건 R2에 남을 수 있다)
    function discard(entry) {
        if (!entry || !entry.result || entry.confirmed) return;
        var payload = JSON.stringify({ url: entry.result.url, token: entry.result.token });
        entry.confirmed = true; // 두 번 보내지 않는다

        if (navigator.sendBeacon) {
            navigator.sendBeacon('/bill/receipt/discard', new Blob([payload], { type: 'application/json' }));
        } else {
            fetch('/bill/receipt/discard', { method: 'POST', body: payload, keepalive: true })
                .catch(function () { /* 못 지워도 사용자가 할 일은 없다 */ });
        }
    }

    function resetPicker() {
        receipt = null;
        picker.classList.remove('filled');
        pickerName.textContent = '사진 첨부하기';
        pickerHint.textContent = '탭해서 영수증 사진을 고르세요';
        pickerHint.classList.remove('warn');
        if (thumb.src) URL.revokeObjectURL(thumb.src);
        thumb.removeAttribute('src');
        thumb.hidden = true;
        bar.hidden = true;
        barFill.style.width = '0';
    }

    fileInput.addEventListener('change', function () {
        var file = fileInput.files && fileInput.files[0];
        if (!file) return resetPicker();

        if (thumb.src) URL.revokeObjectURL(thumb.src);
        thumb.src = URL.createObjectURL(file);
        thumb.hidden = false;
        picker.classList.add('filled');
        pickerName.textContent = file.name || '영수증 사진';
        pickerHint.classList.remove('warn');
        pickerHint.textContent = '사진 준비 중…';
        setProgress(0);

        discard(receipt); // 아까 골랐던 사진은 이제 안 쓴다
        var entry = { name: 'receipt.jpg', blob: file, ready: null, result: null, confirmed: false };
        receipt = entry;

        entry.ready = shrink(file).then(function (blob) {
            if (receipt !== entry) return Promise.reject(new Error('취소됨'));
            entry.blob = blob;
            entry.name = blob === file ? (file.name || 'receipt.jpg') : 'receipt.jpg';
            return upload(blob, entry.name);
        }).then(function (result) {
            if (receipt !== entry) return Promise.reject(new Error('취소됨'));
            bar.hidden = true;
            pickerHint.textContent = '사진 준비 완료 · ' + formatSize(entry.blob.size);
            entry.result = result; // pagehide 에서 동기적으로 읽어야 한다
            return result;
        }).catch(function (error) {
            if (receipt === entry) {
                // 선행 업로드가 실패해도 접수는 된다. 제출할 때 파일을 그대로 붙여 보낸다.
                bar.hidden = true;
                pickerHint.classList.add('warn');
                pickerHint.textContent = '제출할 때 사진을 올릴게요';
            }
            throw error;
        });
    });

    form.addEventListener('submit', function (event) {
        event.preventDefault();
        errorBox.style.display = 'none';
        send();
    });

    function send() {
        var body = new FormData(form);
        var waiting = receipt && receipt.ready;

        setBusy(true, '제출 중…');
        setStatus(waiting ? '사진을 올리고 있어요' : '');

        Promise.resolve(waiting).then(function (ready) {
            if (ready && ready.url) {
                // 이미 올라간 사진이다. 파일 대신 URL + 서명만 보낸다.
                body.delete('receipt');
                body.append('receipt_url', ready.url);
                body.append('receipt_token', ready.token);
            }
        }, function () {
            // 선행 업로드 실패 — 축소본이라도 있으면 그걸 붙인다.
            if (receipt && receipt.blob) body.set('receipt', receipt.blob, receipt.name);
        }).then(function () {
            setStatus('접수하고 있어요');
            return fetch('/bill/submit', { method: 'POST', body: body });
        }).then(function (response) {
            return response.json().catch(function () { return {}; }).then(function (result) {
                if (!response.ok) throw new Error(result.message || '제출에 실패했어요.');
                return result;
            });
        }).then(function (result) {
            if (receipt) receipt.confirmed = true;
            showDone(result.bill);
        }).catch(function (error) {
            showError(error.message || '제출에 실패했어요.');
        }).then(function () {
            setBusy(false);
            setStatus('');
        });
    }

    function showDone(bill) {
        document.getElementById('done-summary').textContent = bill
            ? bill.submitter_name + ' · ' + bill.title + ' · ' + formatWon(bill.amount)
            : '';
        document.getElementById('done-summary').hidden = !bill;
        formView.hidden = true;
        doneView.hidden = false;
        window.scrollTo(0, 0);
    }

    // 한 사람이 여러 건을 이어서 넣는 일이 흔하다. 이름은 남기고 나머지만 비운다.
    document.getElementById('again').addEventListener('click', function () {
        document.getElementById('title').value = '';
        document.getElementById('amount').value = '';
        fileInput.value = '';
        resetPicker();
        errorBox.style.display = 'none';
        doneView.hidden = true;
        formView.hidden = false;
        window.scrollTo(0, 0);
        document.getElementById('title').focus();
    });

    window.addEventListener('pagehide', function () { discard(receipt); });

    document.getElementById('close').addEventListener('click', function () {
        window.close();
        // 스크립트로 연 창이 아니면 close() 가 막힌다. 그럴 땐 안내만 남긴다.
        document.getElementById('close').textContent = '창을 직접 닫아주세요';
        document.getElementById('close').disabled = true;
    });
})();
</script>
</body>
</html>`;
}
