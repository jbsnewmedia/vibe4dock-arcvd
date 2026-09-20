<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vibe4Dock</title>
    <meta name="description" content="arcvd - Application, Root, Chat, Veronica, Diff: one container, one port, all services behind path routing. Part of Vibe4Dock by JBS New Media GmbH.">
    <link rel="icon" type="image/png" href="favicon.png">
    <link rel="icon" type="image/svg+xml" href="logo.svg">
    <meta property="og:title" content="Vibe4Dock - arcvd">
    <meta property="og:description" content="Application, Root, Chat, Veronica, Diff: one container, one port, all services behind path routing.">
    <meta property="og:type" content="website">
    <meta property="og:image" content="favicon.png">
    <style>
        :root {
            --bg: #0f1115;
            --panel: #171a21;
            --border: #2a2f3a;
            --text: #f2f5f7;
            --muted: #a7b0bc;
            --accent: #88eeff;
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            display: grid;
            place-items: center;
            padding: 24px;
            background: var(--bg);
            color: var(--text);
            font: 16px/1.5 "Segoe UI", system-ui, sans-serif;
            overflow-y: scroll;
        }

        .card {
            width: min(760px, 100%);
            background: var(--panel);
            border: 1px solid var(--border);
            border-radius: 16px;
            padding: 28px;
            box-shadow: 0 20px 50px rgba(0, 0, 0, 0.35);
        }

        .brand-icon {
            display: block;
            margin: 0 auto 20px;
        }

        .notice {
            margin-bottom: 22px;
            padding: 14px 16px;
            border: 1px solid rgba(136, 238, 255, 0.25);
            border-radius: 12px;
            background: rgba(136, 238, 255, 0.08);
            color: var(--muted);
        }

        .meta-line {
            margin-top: 6px;
            font-size: 0.95rem;
        }

        .notice strong,
        h1 {
            color: var(--text);
        }

        a {
            color: var(--accent);
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        ul {
            margin: 18px 0 0;
            padding-left: 20px;
        }

        code {
            color: var(--accent);
        }
    </style>
</head>
<body>
<main class="card">
    <svg class="brand-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40.97 40.97" width="76" height="76" role="img" aria-label="Vibe4Dock">
  <path fill="#8ef" d="M284.76,400.47a7.26,7.26,0,0,0-7.26,7.26v26.46a7.25,7.25,0,0,0,7.26,7.25h26.46a7.25,7.25,0,0,0,7.25-7.25V407.73a7.26,7.26,0,0,0-7.25-7.26H284.76" transform="translate(-277.5 -400.47)"/>
  <path fill="#16181d" d="M283.81,408l8.86,8.86a2.88,2.88,0,0,0-.21,1.13v.32h-9v-8.68a3.45,3.45,0,0,1,.37-1.63m-.37,15.59h9v.32a3.16,3.16,0,0,0,.24,1.1l-8.86,8.86a4,4,0,0,1-.4-1.6Zm11.91-5.28h5.27v5.28h-5.27Zm-1.45,8a2.81,2.81,0,0,0,1.13.21h.32v9h-8.69a3.32,3.32,0,0,1-1.62-.37Zm6.72.21H301a3.2,3.2,0,0,0,1.1-.24l8.86,8.86a4.07,4.07,0,0,1-1.6.39h-8.69Zm11.54,7.42-8.86-8.86a2.71,2.71,0,0,0,.22-1.13v-.32h9v8.68a3.33,3.33,0,0,1-.37,1.63m.37-15.59h-9V418a3.16,3.16,0,0,0-.24-1.1l8.85-8.86a4,4,0,0,1,.4,1.6Zm-10.45-2.68a2.88,2.88,0,0,0-1.13-.21h-.33v-9h8.69a3.36,3.36,0,0,1,1.63.37Zm-6.73-.21H295a3.23,3.23,0,0,0-1.11.24l-8.85-8.86a4,4,0,0,1,1.59-.39h8.69ZM281.19,409v9.32h-1.94v5.28h1.94v9.32s0,4.84,4.83,4.84h9.33v1.94h5.27v-1.94H310s4.83,0,4.83-4.84V423.6h1.94v-5.28h-1.94V409s0-4.84-4.83-4.84h-9.33v-1.94h-5.27v1.94H286s-4.83,0-4.83,4.84" transform="translate(-277.5 -400.47)"/>
</svg>
    <div class="notice">
        <a href="https://github.com/jbsnewmedia/vibe4dock-arcvd" target="_blank" rel="noopener noreferrer"><strong>Vibe4Dock</strong></a><br>
        <div class="meta-line">
            Vibe4Dock, Copyright (c) 2026+ JBS New Media GmbH, Juergen Schwind | MIT License |
            <a href="https://github.com/jbsnewmedia/vibe4dock" target="_blank" rel="noopener noreferrer">https://github.com/jbsnewmedia/vibe4dock</a>
        </div>
    </div>

    <h1>Vibe4Dock is running</h1>
    <p>
        Your container setup is ready. Use the browser shells or the tools UI to continue working in this environment.
    </p>
    <ul>
        <li>Chat: <code>/vibe-chat</code></li>
        <li>Veronica: <code>/vibe-veronica</code></li>
        <li>Diff (git): <code>/vibe-diff</code></li>
        <li>Application shell: <code>/vibe-shell-app</code></li>
        <li>Root shell: <code>/vibe-shell-root</code></li>
    </ul>
</main>
</body>
</html>
