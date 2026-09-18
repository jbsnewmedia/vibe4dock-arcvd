/* Chat i18n: de/en dictionaries, browser-language default,
   user choice persisted in localStorage ('vibe4dock.lang'). */
(function () {
    'use strict';

    var LANG_KEY = 'vibe4dock.lang';

    var DICT = {
        de: {
            docTitle: 'Chat - {vibe} - Vibe4Dock',
            newChatBtn: '+ Neuer Chat',
            sidebarTitle: 'Seitenleiste',
            emptyState: 'Frag einfach \u2013 der Agent arbeitet direkt im Projektverzeichnis.',
            workingText: 'Der Agent arbeitet \u2026',
            qmTitle: 'Agent-Fragen',
            closeTitle: 'Schlie\u00dfen',
            agentSelectTitle: 'opencode Agent / Persona',
            modelSelectTitle: 'opencode Modell (Provider/Modell)',
            attachTitle: 'Dateien anh\u00e4ngen (@)',
            promptPh: 'Prompt \u2026 (Enter sendet, Shift+Enter neue Zeile, @ f\u00fcr Dateien, / f\u00fcr Commands)',
            sendBtn: 'Senden',
            dropHtml: 'Dateien ablegen, um sie nach <strong>incoming/</strong> hochzuladen',
            stuckHead: 'Der Agent hat seit \u00fcber einer Minute nicht geantwortet. Falls der Server neu gestartet wurde (z. B. Container-Rebuild), ist die laufende Anfrage verloren gegangen.',
            stuckUnlock: 'Sitzung freigeben',
            stuckWait: 'Weiter warten',
            modelsFav: 'Favoriten',
            modelsRecent: 'K\u00fcrzlich',
            modelsZen: 'OpenCode Zen',
            modelsAll: 'Modelle',
            errPrefix: 'Fehler: ',
            cmdErr: 'Command-Fehler: ',
            providerHint: 'Hinweis: Ist ein Provider konfiguriert? In der Anwendungshell <code>opencode auth login</code> ausf\u00fchren oder den Container neu aufbauen.',
            thinkingTools: 'Denkt & arbeitet',
            permPrefix: 'Freigabe: ',
            permAction: 'Aktion',
            permAllow: 'Erlauben',
            permAlways: 'Immer erlauben',
            permDeny: 'Ablehnen',
            question: 'Frage',
            ownAnswerPh: 'Eigene Antwort (optional)',
            answerRequired: 'Bitte beantworte diese Frage \u2013 Option w\u00e4hlen oder eigene Antwort tippen.',
            sendAnswer: 'Antwort senden',
            uploadPct: 'Lade {name} {pct}% hoch',
            uploadIdx: 'Lade {name} {i}/{n} hoch',
            uploadFailed: 'Upload fehlgeschlagen: {name}',
            attached: 'Angeh\u00e4ngt: {name}',
            sessionChat: 'Chat',
            deleteChatTitle: 'Chat l\u00f6schen',
            showQuestions: 'Fragen anzeigen ({n})',
            cmdFilter: '{m} von {n} Commands \u2013 tippen zum Filtern'
        },
        en: {
            docTitle: 'Chat - {vibe} - Vibe4Dock',
            newChatBtn: '+ New chat',
            sidebarTitle: 'Toggle sidebar',
            emptyState: 'Ask anything \u2013 the agent works directly in the project directory.',
            workingText: 'The agent is working \u2026',
            qmTitle: 'Agent questions',
            closeTitle: 'Close',
            agentSelectTitle: 'opencode agent / persona',
            modelSelectTitle: 'opencode model (provider/model)',
            attachTitle: 'Attach files (@)',
            promptPh: 'Prompt \u2026 (Enter to send, Shift+Enter for a newline, @ for files, / for commands)',
            sendBtn: 'Send',
            dropHtml: 'Drop files to upload them to <strong>incoming/</strong>',
            stuckHead: 'The agent has not responded for over a minute. If the server was restarted (e.g. a container rebuild), the running request and any pending question were lost.',
            stuckUnlock: 'Unlock session',
            stuckWait: 'Keep waiting',
            modelsFav: 'Favorites',
            modelsRecent: 'Recent',
            modelsZen: 'OpenCode Zen',
            modelsAll: 'Models',
            errPrefix: 'Error: ',
            cmdErr: 'Command error: ',
            providerHint: 'Hint: Is a provider configured? Run <code>opencode auth login</code> in the application shell or rebuild the container.',
            thinkingTools: 'Thinking &amp; Tools',
            permPrefix: 'Permission: ',
            permAction: 'action',
            permAllow: 'Allow',
            permAlways: 'Always allow',
            permDeny: 'Deny',
            question: 'Question',
            ownAnswerPh: 'Custom answer (optional)',
            answerRequired: 'Please answer this question - pick an option or type a custom answer.',
            sendAnswer: 'Send answer',
            uploadPct: 'Uploading {name} {pct}%',
            uploadIdx: 'Uploading {name} {i}/{n}',
            uploadFailed: 'Upload failed: {name}',
            attached: 'Attached: {name}',
            sessionChat: 'Chat',
            deleteChatTitle: 'Delete chat',
            showQuestions: 'Show questions ({n})',
            cmdFilter: '{m} of {n} commands - type to filter'
        }
    };

    window.I18N = (function () {
        var lang = 'en';
        var langs = Object.keys(DICT);

        function detect() {
            try {
                var saved = localStorage.getItem(LANG_KEY);
                if (saved && langs.indexOf(saved) !== -1) return saved;
            } catch (e) { /* storage blocked */ }
            var nav = ((navigator.languages && navigator.languages[0]) ||
                navigator.language || (navigator.userLanguage || 'en')).toLowerCase();
            for (var i = 0; i < langs.length; i++) {
                if (nav.indexOf(langs[i]) === 0) return langs[i];
            }
            return 'en';
        }

        var VIBE_NAME = (window.CHAT_CONFIG && window.CHAT_CONFIG.vibeName) || 'Vibe4Dock';

        function interpolate(s, vars) {
            s = s.replace(/\{vibe\}/g, VIBE_NAME);
            if (!vars) return s;
            return s.replace(/\{(\w+)\}/g, function (m, k) {
                return (vars[k] !== undefined) ? String(vars[k]) : m;
            });
        }

        function t(key, vars) {
            var entry = DICT[lang][key];
            if (entry === undefined) entry = DICT.en[key];
            if (entry === undefined) entry = key;
            return interpolate(entry, vars);
        }

        function raw(key) {
            var entry = DICT[lang][key];
            if (entry === undefined) entry = DICT.en[key];
            return entry;
        }

        function apply(root) {
            root = root || document;
            var nodes = root.querySelectorAll('[data-i18n]');
            for (var i = 0; i < nodes.length; i++) {
                nodes[i].textContent = t(nodes[i].getAttribute('data-i18n'));
            }
            nodes = root.querySelectorAll('[data-i18n-placeholder]');
            for (i = 0; i < nodes.length; i++) {
                nodes[i].placeholder = t(nodes[i].getAttribute('data-i18n-placeholder'));
            }
            nodes = root.querySelectorAll('[data-i18n-title]');
            for (i = 0; i < nodes.length; i++) {
                nodes[i].title = t(nodes[i].getAttribute('data-i18n-title'));
            }
            nodes = root.querySelectorAll('[data-i18n-html]');
            for (i = 0; i < nodes.length; i++) {
                nodes[i].innerHTML = t(nodes[i].getAttribute('data-i18n-html'));
            }
            var sw = root.querySelectorAll('.lang-switch');
            for (i = 0; i < sw.length; i++) {
                var btns = sw[i].querySelectorAll('button[data-lang]');
                for (var j = 0; j < btns.length; j++) {
                    var active = btns[j].getAttribute('data-lang') === lang;
                    btns[j].classList.toggle('active', active);
                }
            }
            document.documentElement.lang = lang;
        }

        function setLang(l) {
            if (langs.indexOf(l) === -1 || l === lang) return;
            lang = l;
            try { localStorage.setItem(LANG_KEY, l); } catch (e) { /* storage blocked */ }
            apply();
            document.dispatchEvent(new CustomEvent('i18n:change', { detail: { lang: lang } }));
        }

        lang = detect();

        document.addEventListener('click', function (e) {
            var btn = e.target && e.target.closest ? e.target.closest('.lang-switch button[data-lang]') : null;
            if (btn) setLang(btn.getAttribute('data-lang'));
        });

        return { t: t, raw: raw, apply: apply, setLang: setLang, lang: function () { return lang; } };
    })();

    window.t = function (key, vars) { return window.I18N.t(key, vars); };

    window.I18N.apply();
})();
