<?php
/**
 * Vibe-Diff: git working tree UI (branches, commits, changed files,
 * unified diff, line/block revert like an IDE).
 *
 * Repo path comes from VIBE_DIFF_REPO (default: parent of the webroot).
 * Access control (HTTP Basic Auth) is enforced by the Apache <Location>
 * block generated at container start.
 */

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '1');

/* ------------------------------------------------------------------ i18n */

$LANGS = ['de', 'en'];

function lang(): string
{
    $cookie = $_COOKIE['vibe4dock.lang'] ?? '';
    if (in_array($cookie, $GLOBALS['LANGS'], true)) {
        return $cookie;
    }
    return 'en';
}

$T = [
    'en' => [
        'title' => 'Diff', 'repo' => 'Repository', 'branch' => 'Branch', 'detached' => 'detached',
        'branches' => 'Branches', 'checkout' => 'Checkout', 'commits' => 'Commits', 'useAsBase' => 'compare',
        'changes' => 'Changed files', 'noChanges' => 'No changes vs base.', 'base' => 'Compare with',
        'back' => 'Overview', 'revertFile' => 'Revert file', 'revertSelected' => 'Revert selected',
        'revertBlock' => 'Revert block', 'confirmFile' => 'Revert ALL changes in this file?',
        'confirmCheckout' => 'Checkout branch?', 'deleteUntracked' => 'Delete untracked file?',
        'newFile' => 'new file', 'deleted' => 'deleted', 'renamed' => 'renamed',
        'binary' => 'Binary file - no diff shown.', 'hintDeletions' => 'Pure deletions are restored via "Revert block".',
        'selectHint' => 'Tick lines, then "Revert selected" - changed lines are restored to their original state.',
        'error' => 'Error', 'ok' => 'OK', 'working' => 'Working tree', 'diffTo' => 'Diff',
        'lgMod' => 'modified', 'lgAdd' => 'added (staged)', 'lgDel' => 'deleted', 'lgRen' => 'renamed', 'lgUnt' => 'untracked',
        'footer' => 'Part of <strong>Vibe4Dock</strong> &middot; &copy; 2026+ <a href="https://jbs-newmedia.com" target="_blank" rel="noopener noreferrer">JBS New Media GmbH</a> &middot; Juergen Schwind &middot; <a href="https://github.com/jbsnewmedia/vibe4dock" target="_blank" rel="noopener noreferrer">vibe4dock</a> &middot; MIT License',
    ],
    'de' => [
        'title' => 'Diff', 'repo' => 'Repository', 'branch' => 'Branch', 'detached' => 'detached',
        'branches' => 'Branches', 'checkout' => 'Wechseln', 'commits' => 'Commits', 'useAsBase' => 'vergleichen',
        'changes' => 'Geänderte Dateien', 'noChanges' => 'Keine Änderungen gegenüber Base.', 'base' => 'Vergleichen mit',
        'back' => 'Übersicht', 'revertFile' => 'Datei zurücksetzen', 'revertSelected' => 'Auswahl zurücksetzen',
        'revertBlock' => 'Block zurücksetzen', 'confirmFile' => 'ALLE Änderungen in dieser Datei zurücksetzen?',
        'confirmCheckout' => 'Branch wechseln?', 'deleteUntracked' => 'Unversionierte Datei löschen?',
        'newFile' => 'neue Datei', 'deleted' => 'gelöscht', 'renamed' => 'umbenannt',
        'binary' => 'Binärdatei – kein Diff.', 'hintDeletions' => 'Reine Löschungen werden über "Block zurücksetzen" wiederhergestellt.',
        'selectHint' => 'Zeilen anhaken, dann "Auswahl zurücksetzen" – geänderte Zeilen kehren zum Original zurück.',
        'error' => 'Fehler', 'ok' => 'OK', 'working' => 'Arbeitskopie', 'diffTo' => 'Diff',
        'lgMod' => 'geändert', 'lgAdd' => 'neu (staged)', 'lgDel' => 'gelöscht', 'lgRen' => 'umbenannt', 'lgUnt' => 'unversioniert',
        'footer' => 'Part of <strong>Vibe4Dock</strong> &middot; &copy; 2026+ <a href="https://jbs-newmedia.com" target="_blank" rel="noopener noreferrer">JBS New Media GmbH</a> &middot; Juergen Schwind &middot; <a href="https://github.com/jbsnewmedia/vibe4dock" target="_blank" rel="noopener noreferrer">vibe4dock</a> &middot; MIT License',
    ],
];

function t(string $k): string
{
    $l = lang();
    return $GLOBALS['T'][$l][$k] ?? $GLOBALS['T']['en'][$k] ?? $k;
}

/* ------------------------------------------------------------- repo setup */

$VIBE_NAME = preg_replace('/["\\\\|]/', '', getenv('VIBE_NAME') ?: 'Vibe4Dock') ?: 'Vibe4Dock';
$REPO = getenv('VIBE_DIFF_REPO') ?: '/app';
$REPO_REAL = realpath($REPO);
$P = preg_replace('/[^a-z0-9_-]/i', '', getenv('VIBE_PREFIX') ?: 'vibe') ?: 'vibe';
$BASEURL = '/' . $P . '-diff/';

if ($REPO_REAL === false || !is_dir($REPO_REAL . '/.git')) {
    http_response_code(500);
    $lang = lang();
    $msg = $lang === 'de'
        ? 'Kein Git-Repository unter <code>' . htmlspecialchars($REPO) . '</code>. Projekt-Repo einbinden und <code>VIBE_DIFF_REPO</code> setzen (Default: Webroot-Elternverzeichnis).'
        : 'No git repository at <code>' . htmlspecialchars($REPO) . '</code>. Mount the project repo and set <code>VIBE_DIFF_REPO</code> (default: parent of the webroot).';
    echo '<!doctype html><meta charset="utf-8"><title>Vibe-Diff</title><body style="font-family:monospace;background:#16181d;color:#e6e6e6;padding:40px"><h1 style="color:#88eeff">Vibe-Diff</h1><p>' . $msg . '</p></body>';
    exit;
}

function run(array $args, ?string $stdin = null): array
{
    global $REPO_REAL;
    $cmd = 'git -C ' . escapeshellarg($REPO_REAL) . ' -c core.quotepath=false';
    foreach ($args as $a) {
        $cmd .= ' ' . escapeshellarg($a);
    }
    $spec = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $proc = proc_open($cmd, $spec, $pipes);
    if (!is_resource($proc)) {
        return ['code' => -1, 'out' => '', 'err' => 'proc_open failed'];
    }
    if ($stdin !== null) {
        fwrite($pipes[0], $stdin);
    }
    fclose($pipes[0]);
    $out = stream_get_contents($pipes[1]) ?: '';
    $err = stream_get_contents($pipes[2]) ?: '';
    fclose($pipes[1]);
    fclose($pipes[2]);
    $code = proc_close($proc);
    return ['code' => $code, 'out' => $out, 'err' => trim($err)];
}

function refValid(string $ref): bool
{
    if (!preg_match('/^[A-Za-z0-9][A-Za-z0-9._\/-]{0,180}$/', $ref) || str_contains($ref, '..')) {
        return false;
    }
    return run(['rev-parse', '--verify', '--quiet', $ref . '^{commit}'])['code'] === 0;
}

function insideRepo(string $rel): ?string
{
    global $REPO_REAL;
    $rel = ltrim(str_replace('\\', '/', $rel), '/');
    if ($rel === '' || str_contains($rel, '..') || preg_match('#(^|/)\.git(/|$)#', $rel)) {
        return null;
    }
    $abs = realpath($REPO_REAL . '/' . $rel);
    if ($abs === false || !str_starts_with($abs, $REPO_REAL . DIRECTORY_SEPARATOR)) {
        return null;
    }
    return $abs;
}

function isTracked(string $rel): bool
{
    return run(['ls-files', '--error-unmatch', '--', $rel])['code'] === 0;
}

function statusEntries(): array
{
    $r = run(['status', '--porcelain', '-z', '-uall']);
    if ($r['code'] !== 0) {
        return [];
    }
    $parts = explode("\0", $r['out']);
    $out = [];
    $i = 0;
    while ($i < count($parts)) {
        $e = $parts[$i];
        if ($e === '') {
            $i++;
            continue;
        }
        $xy = substr($e, 0, 2);
        $path = substr($e, 3);
        $old = null;
        if (in_array($xy[0], ['R', 'C'], true) || in_array($xy[1], ['R', 'C'], true)) {
            $old = $parts[$i + 1] ?? null;
            $i++;
        }
        $out[] = ['xy' => $xy, 'path' => $path, 'old' => $old];
        $i++;
    }
    return $out;
}

/* ----------------------------------------------------------- diff parsing */

function parseUnifiedDiff(string $diff): array
{
    $hunks = [];
    $cur = null;
    $old = 0;
    $new = 0;
    foreach (explode("\n", $diff) as $line) {
        if (preg_match('/^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/', $line, $m)) {
            $old = (int) $m[1];
            $new = (int) $m[3];
            $cur = ['oldStart' => $old, 'oldCount' => (int) ($m[2] ?? 1), 'newStart' => $new, 'newCount' => (int) ($m[4] ?? 1), 'lines' => []];
            $hunks[] = $cur;
            continue;
        }
        if ($cur === null || $line === '') {
            continue;
        }
        $c = $line[0];
        $text = substr($line, 1);
        if ($c === '\\') {
            $cur['lines'][] = ['type' => 'notice', 'text' => $line];
        } elseif ($c === ' ') {
            $cur['lines'][] = ['type' => 'ctx', 'old' => $old++, 'new' => $new++, 'text' => $text];
        } elseif ($c === '-') {
            $cur['lines'][] = ['type' => 'del', 'old' => $old++, 'text' => $text];
        } elseif ($c === '+') {
            $cur['lines'][] = ['type' => 'add', 'new' => $new++, 'text' => $text];
        }
        $hunks[count($hunks) - 1] = $cur;
    }
    foreach ($hunks as $i => $h) {
        $realNew = 0;
        foreach ($h['lines'] as $ln) {
            if (in_array($ln['type'], ['ctx', 'add'], true)) {
                $realNew++;
            }
        }
        $hunks[$i]['newCount'] = $realNew;
    }
    return $hunks;
}

function splitHunks(string $diff): array
{
    $header = '';
    $hunks = [];
    $cur = null;
    foreach (explode("\n", $diff) as $line) {
        if ($line === '') {
            continue;
        }
        if (str_starts_with($line, '@@ ')) {
            if ($cur !== null) {
                $hunks[] = $cur;
            }
            $cur = $line . "\n";
            continue;
        }
        if ($cur === null) {
            $header .= $line . "\n";
        } else {
            $cur .= $line . "\n";
        }
    }
    if ($cur !== null) {
        $hunks[] = $cur;
    }
    return ['header' => $header, 'hunks' => $hunks];
}

function synthAddedHunks(string $abs): array
{
    $raw = file_get_contents($abs);
    if ($raw === false || $raw === '') {
        return [];
    }
    $lines = explode("\n", rtrim($raw, "\n"));
    return [[
        'oldStart' => 0,
        'oldCount' => 0,
        'newStart' => 1,
        'newCount' => count($lines),
        'lines' => array_map(
            fn (int $i, string $txt): array => ['type' => 'add', 'new' => $i + 1, 'text' => $txt],
            array_keys($lines),
            array_values($lines)
        ),
    ]];
}

function revertLinesInFile(string $abs, array $hunks, array $selected): void
{
    $raw = file_get_contents($abs);
    $lines = explode("\n", rtrim($raw, "\n"));
    $hadFinalNl = str_ends_with($raw, "\n");
    $out = [];
    $pos = 1;
    foreach ($hunks as $h) {
        $newStart = max(1, $h['newStart']);
        for ($i = $pos; $i < $newStart && $i <= count($lines); $i++) {
            $out[] = $lines[$i - 1];
        }
        $removedQ = [];
        foreach ($h['lines'] as $ln) {
            if ($ln['type'] === 'notice') {
                continue;
            }
            if ($ln['type'] === 'ctx') {
                $out[] = $lines[$ln['new'] - 1];
            } elseif ($ln['type'] === 'del') {
                $removedQ[] = $ln['text'];
            } elseif (in_array($ln['new'], $selected, true)) {
                if ($removedQ) {
                    $out[] = array_shift($removedQ);
                }
                // else: pure addition -> drop the line
            } else {
                if ($removedQ) {
                    array_shift($removedQ);
                }
                $out[] = $lines[$ln['new'] - 1];
            }
        }
        $pos = $newStart + max(0, $h['newCount']);
    }
    for ($i = $pos; $i <= count($lines); $i++) {
        $out[] = $lines[$i - 1];
    }
    $content = implode("\n", $out);
    if ($hadFinalNl && $content !== '') {
        $content .= "\n";
    }
    file_put_contents($abs, $content);
}

function removeLineRange(string $abs, int $start, int $count): void
{
    $lines = file($abs, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    array_splice($lines, $start - 1, $count);
    file_put_contents($abs, implode("\n", $lines) . "\n");
}

/* --------------------------------------------------------------- router */

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$input = [];
if ($method === 'POST') {
    $input = json_decode(file_get_contents('php://input') ?: '[]', true) ?: [];
}
$action = $input['action'] ?? ($_GET['action'] ?? null);

/* ------------------------------------------------------------ POST APIs */

if ($method === 'POST' && $action !== null) {
    header('Content-Type: application/json; charset=utf-8');
    $reply = fn (bool $ok, string $msg = '') => json_encode(['ok' => $ok, 'message' => $msg]);
    $file = (string) ($input['file'] ?? '');
    $base = (string) ($input['base'] ?? 'HEAD');

    if ($action === 'checkout') {
        $branch = (string) ($input['branch'] ?? '');
        if (!refValid($branch)) {
            die($reply(false, 'invalid branch'));
        }
        $r = run(['checkout', $branch]);
        die($reply($r['code'] === 0, $r['code'] === 0 ? 'checked out ' . $branch : $r['err']));
    }

    $abs = insideRepo($file);
    if ($abs === null || !file_exists($abs)) {
        die($reply(false, 'invalid file'));
    }
    if (!refValid($base)) {
        die($reply(false, 'invalid base'));
    }
    $tracked = isTracked($file);

    if ($action === 'revert_file') {
        if (!$tracked) {
            die($reply(@unlink($abs) ? true : false, 'untracked file removed'));
        }
        $r = run(['restore', '--source=' . $base, '--staged', '--worktree', '--', $file]);
        die($reply($r['code'] === 0, $r['code'] === 0 ? 'reverted ' . $file : $r['err']));
    }

    $hunks = [];
    if ($tracked) {
        $r = run(['diff', $base, '--', $file]);
        if ($r['code'] !== 0) {
            die($reply(false, $r['err']));
        }
        $hunks = parseUnifiedDiff($r['out']);
        $rawDiff = $r['out'];
    } else {
        $hunks = synthAddedHunks($abs);
    }

    if ($action === 'revert_hunk') {
        $idx = (int) ($input['hunk'] ?? -1);
        if (!isset($hunks[$idx])) {
            die($reply(false, 'invalid hunk'));
        }
        if (!$tracked) {
            removeLineRange($abs, $hunks[$idx]['newStart'], $hunks[$idx]['newCount']);
            die($reply(true, 'block removed'));
        }
        $parts = splitHunks($rawDiff);
        if (!isset($parts['hunks'][$idx])) {
            die($reply(false, 'invalid hunk patch'));
        }
        $r = run(['apply', '-R', '--recount', '--whitespace=nowarn'], $parts['header'] . $parts['hunks'][$idx]);
        die($reply($r['code'] === 0, $r['code'] === 0 ? 'block reverted' : $r['err']));
    }

    if ($action === 'revert_lines') {
        $sel = array_values(array_filter(array_map('intval', $input['lines'] ?? [])));
        if (!$sel) {
            die($reply(false, 'no lines selected'));
        }
        if (!$tracked) {
            $lines = file($abs, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            $keep = array_diff(range(1, count($lines)), $sel);
            $content = '';
            foreach ($keep as $n) {
                $content .= ($lines[$n - 1] ?? '') . "\n";
            }
            file_put_contents($abs, $content);
            die($reply(true, 'lines removed'));
        }
        revertLinesInFile($abs, $hunks, $sel);
        die($reply(true, 'lines reverted'));
    }

    die($reply(false, 'unknown action'));
}

/* ------------------------------------------------------------ view data */

$base = (string) ($_GET['base'] ?? 'HEAD');
if (!refValid($base)) {
    $base = 'HEAD';
}

$headBranch = trim(run(['rev-parse', '--abbrev-ref', 'HEAD'])['out']);
$headHash = substr(trim(run(['rev-parse', 'HEAD'])['out']), 0, 8);
$branches = array_filter(array_map('trim', explode("\n", run(['branch', '--format=%(refname:short)'])['out'])));
$remotes = array_filter(array_map('trim', explode("\n", run(['branch', '-r', '--format=%(refname:short)'])['out'])));
$logLines = array_filter(explode("\n", run(['log', '--pretty=%h%x09%an%x09%ad%x09%s', '--date=short', '-n', '50'])['out']));
$status = statusEntries();

$view = (string) ($_GET['view'] ?? 'home');
$file = (string) ($_GET['file'] ?? '');
$abs = null;
$hunks = [];
$binary = false;
$untracked = false;
$tracked = false;

    if ($view === 'diff' && $file !== '') {
        $abs = insideRepo($file);
        if ($abs === null || !file_exists($abs)) {
            $view = 'home';
        } else {
            $tracked = isTracked($file);
            $untracked = !$tracked;
            if ($tracked) {
                $r = run(['diff', $base, '--', $file]);
                $rawDiff = $r['out'];
                $binary = str_contains($rawDiff, 'Binary files') || str_contains($rawDiff, 'GIT binary patch');
                $hunks = $binary ? [] : parseUnifiedDiff($rawDiff);
            } else {
                $hunks = synthAddedHunks($abs);
            }
        }
    }

$esc = htmlspecialchars(...);
$selCount = 0;
?>
<!doctype html>
<html lang="<?= $esc(lang()) ?>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= $esc(t('title')) ?> - <?= $esc($VIBE_NAME) ?> - Vibe4Dock</title>
<link rel="stylesheet" href="style.css?v=<?= filemtime(__DIR__ . '/style.css') ?>">
</head>
<body>
<header id="topbar">
    <a class="brand" href="<?= $BASEURL ?>?base=<?= urlencode($base) ?>">Vibe-<b>Diff</b></a>
    <span class="repo" title="<?= $esc($REPO) ?>"><?= $esc(basename($REPO_REAL)) ?></span>
    <span class="branch-chip"><?= $esc($headBranch === 'HEAD' ? t('detached') . ' ' . $headHash : $headBranch) ?></span>
    <form method="get" class="base-form">
        <input type="hidden" name="view" value="<?= $esc($view) ?>">
        <input type="hidden" name="file" value="<?= $esc($file) ?>">
        <label for="base"><?= $esc(t('base')) ?>:</label>
        <select name="base" id="base" onchange="this.form.submit()">
            <?php foreach (array_merge(['HEAD'], $branches, $remotes) as $b): ?>
                <option value="<?= $esc($b) ?>" <?= $b === $base ? 'selected' : '' ?>><?= $esc($b) ?></option>
            <?php endforeach; ?>
        </select>
        <noscript><button type="submit"><?= $esc(t('ok')) ?></button></noscript>
    </form>
    <span class="lang-switch" role="group" aria-label="Language">
        <button type="button" data-lang="de">DE</button><button type="button" data-lang="en">EN</button>
    </span>
</header>

<?php if ($view === 'diff' && $abs !== null): ?>
<main>
    <div class="filebar">
        <a class="btn" href="<?= $BASEURL ?>?base=<?= urlencode($base) ?>">&larr; <?= $esc(t('back')) ?></a>
        <span class="path"><?= $esc($file) ?></span>
        <?php if ($untracked): ?><span class="badge badge-a"><?= $esc(t('newFile')) ?></span><?php endif; ?>
        <span class="spacer"></span>
        <span class="hint"><?= $esc(t('selectHint')) ?></span>
        <button class="btn primary" id="revert-selected" disabled><?= $esc(t('revertSelected')) ?> (<span id="sel-count">0</span>)</button>
        <button class="btn danger" id="revert-file"><?= $esc(t('revertFile')) ?></button>
    </div>

    <?php if ($binary): ?>
        <div class="empty"><?= $esc(t('binary')) ?></div>
    <?php elseif (!$hunks): ?>
        <div class="empty"><?= $esc(t('noChanges')) ?></div>
    <?php else: ?>
        <?php if (!$untracked && $tracked): ?>
        <div class="notedeletions"><?= $esc(t('hintDeletions')) ?></div>
        <?php endif; ?>
        <?php $hunkNo = -1; foreach ($hunks as $hunk): $hunkNo++; ?>
        <div class="hunk" data-hunk="<?= $hunkNo ?>">
            <div class="hunk-head">
                <span class="hunk-range">@<?= $hunkNo + 1 ?> &nbsp;@@ -<?= $hunk['oldStart'] ?>,<?= $hunk['oldCount'] ?> +<?= $hunk['newStart'] ?>,<?= $hunk['newCount'] ?> @@</span>
                <button class="btn small revert-hunk" data-hunk="<?= $hunkNo ?>"><?= $esc(t('revertBlock')) ?></button>
            </div>
            <table class="diff">
                <tbody>
                <?php foreach ($hunk['lines'] as $ln):
                    if ($ln['type'] === 'notice'): ?>
                        <tr class="notice"><td colspan="4"><?= $esc($ln['text']) ?></td></tr>
                    <?php continue; endif;
                    $isAdd = $ln['type'] === 'add';
                    $isDel = $ln['type'] === 'del';
                    $cls = $isAdd ? 'add' : ($isDel ? 'del' : 'ctx');
                ?>
                <tr class="<?= $cls ?>">
                    <td class="no"><?= isset($ln['old']) ? $ln['old'] : '' ?></td>
                    <td class="no"><?= isset($ln['new']) ? $ln['new'] : '' ?></td>
                    <td class="chk"><?php if ($isAdd): ?><input type="checkbox" class="linechk" data-line="<?= $ln['new'] ?>"><?php endif; ?></td>
                    <td class="code"><pre><?= $esc($ln['text']) ?></pre></td>
                </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endforeach; ?>
    <?php endif; ?>
</main>
<script>
window.VIBE_DIFF = {
    baseurl: <?= json_encode($BASEURL) ?>,
    file: <?= json_encode($file) ?>,
    base: <?= json_encode($base) ?>,
    untracked: <?= json_encode($untracked) ?>
};
</script>
<script src="app.js?v=<?= filemtime(__DIR__ . '/app.js') ?>"></script>

<?php else: ?>
<main>
    <div class="grid2">
        <section class="card">
            <h2><?= $esc(t('branches')) ?></h2>
            <table class="list">
                <?php foreach ($branches as $b): ?>
                <tr class="<?= $b === $headBranch ? 'current' : '' ?>">
                    <td><?= $esc($b) ?><?= $b === $headBranch ? ' &larr;' : '' ?></td>
                    <td class="ta-r">
                        <?php if ($b !== $headBranch): ?>
                        <button class="btn small checkout" data-branch="<?= $esc($b) ?>"><?= $esc(t('checkout')) ?></button>
                        <?php endif; ?>
                    </td>
                </tr>
                <?php endforeach; ?>
                <?php foreach ($remotes as $b): ?>
                <tr class="remote"><td><?= $esc($b) ?></td><td></td></tr>
                <?php endforeach; ?>
            </table>
        </section>
        <section class="card">
            <h2><?= $esc(t('commits')) ?> <span class="muted">(<?= $esc(t('working')) ?> &harr; base)</span></h2>
            <table class="list">
                <?php foreach (array_slice($logLines, 0, 50) as $row):
                    [$h, $an, $ad, $s] = array_pad(explode("\t", $row, 4), 4, ''); ?>
                <tr>
                    <td class="hash"><?= $esc($h) ?></td>
                    <td class="muted"><?= $esc($an) ?>, <?= $esc($ad) ?></td>
                    <td><?= $esc($s) ?></td>
                    <td class="ta-r"><a class="btn small" href="<?= $BASEURL ?>?base=<?= urlencode($h) ?>"><?= $esc(t('useAsBase')) ?></a></td>
                </tr>
                <?php endforeach; ?>
            </table>
        </section>
    </div>

    <section class="card">
        <h2><?= $esc(t('changes')) ?> <span class="muted"><?= $esc(t('diffTo')) ?>: <?= $esc($base) ?></span></h2>
        <div class="legend">
            <span><span class="badge badge-m">M</span> <?= $esc(t('lgMod')) ?></span>
            <span><span class="badge badge-a">A</span> <?= $esc(t('lgAdd')) ?></span>
            <span><span class="badge badge-d">D</span> <?= $esc(t('lgDel')) ?></span>
            <span><span class="badge badge-m">R</span> <?= $esc(t('lgRen')) ?></span>
            <span><span class="badge badge-u">??</span> <?= $esc(t('lgUnt')) ?></span>
        </div>
        <?php if (!$status): ?>
            <div class="empty"><?= $esc(t('noChanges')) ?></div>
        <?php else: ?>
        <table class="list files">
            <?php foreach ($status as $e):
                $x = $e['xy'][0]; $y = $e['xy'][1];
                $badge = $x === '?' ? 'badge-u' : (str_contains('MART', $y) && $y !== ' ' ? 'badge-m' : ($y === 'D' || $x === 'D' ? 'badge-d' : 'badge-m'));
                if ($x === 'A' || $y === 'A') $badge = 'badge-a';
                if ($x === 'D' || $y === 'D') $badge = 'badge-d';
                if ($x === '?' ) $badge = 'badge-u';
            ?>
            <tr>
                <td><span class="badge <?= $badge ?>"><?= $esc($e['xy']) ?></span></td>
                <td><a class="filelink" href="<?= $BASEURL ?>?view=diff&base=<?= urlencode($base) ?>&file=<?= urlencode($e['path']) ?>"><?= $esc($e['path']) ?></a><?php if ($e['old']): ?> <span class="muted">&larr; <?= $esc(t('renamed')) ?>: <?= $esc($e['old']) ?></span><?php endif; ?></td>
                <td class="ta-r"><a class="btn small" href="<?= $BASEURL ?>?view=diff&base=<?= urlencode($base) ?>&file=<?= urlencode($e['path']) ?>"><?= $esc(t('diffTo')) ?></a></td>
            </tr>
            <?php endforeach; ?>
        </table>
        <?php endif; ?>
    </section>
</main>
<script src="app.js?v=<?= filemtime(__DIR__ . '/app.js') ?>"></script>
<?php endif; ?>

<footer id="vibe-footer"><?= t('footer') ?></footer>
</body>
</html>
