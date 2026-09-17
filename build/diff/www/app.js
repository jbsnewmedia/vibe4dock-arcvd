(function () {
    'use strict';

    /* language switch: cookie + reload (server-rendered texts) */
    document.addEventListener('click', function (e) {
        var btn = e.target && e.target.closest ? e.target.closest('.lang-switch button[data-lang]') : null;
        if (!btn) return;
        var l = btn.getAttribute('data-lang');
        var url = new URL(location.href);
        url.searchParams.set('lang', l);
        document.cookie = 'vibe4dock.lang=' + l + ';path=/;max-age=31536000;samesite=lax';
        location.href = url.toString();
    });

    var cfg = window.VIBE_DIFF;
    if (!cfg) return;

    function api(action, body) {
        return fetch(location.origin + cfg.baseurl + '?action=' + encodeURIComponent(action), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(Object.assign({ action: action, file: cfg.file, base: cfg.base }, body))
        }).then(function (r) { return r.json(); });
    }

    function done(res) {
        if (!res.ok) { alert(res.message || 'Error'); return; }
        location.reload();
    }

    /* diff view: selection counter + revert actions */
    var selBtn = document.getElementById('revert-selected');
    var countEl = document.getElementById('sel-count');
    var checks = Array.prototype.slice.call(document.querySelectorAll('.linechk'));

    function updateCount() {
        var n = checks.filter(function (c) { return c.checked; }).length;
        if (countEl) countEl.textContent = String(n);
        if (selBtn) selBtn.disabled = n === 0;
    }
    checks.forEach(function (c) { c.addEventListener('change', updateCount); });

    if (selBtn) {
        selBtn.addEventListener('click', function () {
            var lines = checks.filter(function (c) { return c.checked; })
                .map(function (c) { return parseInt(c.dataset.line, 10); });
            if (!lines.length) return;
            api('revert_lines', { lines: lines }).then(done);
        });
    }

    document.querySelectorAll('.revert-hunk').forEach(function (b) {
        b.addEventListener('click', function () {
            api('revert_hunk', { hunk: parseInt(b.dataset.hunk, 10) }).then(done);
        });
    });

    var revertFile = document.getElementById('revert-file');
    if (revertFile) {
        revertFile.addEventListener('click', function () {
            var msg = cfg.untracked ? 'Delete untracked file?' : 'Revert ALL changes in this file?';
            if (!confirm(msg)) return;
            api('revert_file', {}).then(done);
        });
    }

    /* home view: branch checkout */
    document.querySelectorAll('.checkout').forEach(function (b) {
        b.addEventListener('click', function () {
            if (!confirm('Checkout branch "' + b.dataset.branch + '"?')) return;
            fetch(location.origin + cfg.baseurl + '?action=checkout', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'checkout', branch: b.dataset.branch })
            }).then(function (r) { return r.json(); }).then(done);
        });
    });
})();
