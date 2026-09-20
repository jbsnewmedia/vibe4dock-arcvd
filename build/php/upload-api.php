<?php
/**
 * Chat/Veronica file upload endpoints (arcvd all-in-one image).
 *
 * Served by Apache (php-fpm) at /{VIBE_PREFIX}-{chat,veronica}/api/upload{,/list,/file}.
 * Access control (HTTP Basic Auth) is enforced by the Apache <Location> block
 * generated at container start - this script never runs unauthenticated
 * through normal routing.
 *
 * Files are stored in the project's incoming/ directory so the agent can
 * reference them via @name.
 *
 * POST /api/upload        multipart field "file" (single or array)
 *                         -> {"ok":true,"files":[{"ok":true,"name":"..","path":"incoming/..","size":123}, ..]}
 * GET  /api/upload/list   -> {"ok":true,"files":[{"name","path","size","mtime"}, ..]} (newest first)
 * GET  /api/upload/file   ?name=.. -> raw file (inline preview for known types)
 * else                    -> 405
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

$incomingDir = getenv('VIBE_INCOMING_DIR');
if ($incomingDir === false || $incomingDir === '') {
    $incomingDir = '/app/project/incoming';
}

/**
 * Routing: the Apache Alias maps upload, upload/list and upload/file to this
 * script, so the action is derived from the original request URI.
 */
function requestAction(): string
{
    $uri = (string) ($_SERVER['REQUEST_URI'] ?? '');
    $path = (string) (parse_url($uri, PHP_URL_PATH) ?: $uri);
    $base = basename($path);

    return in_array($base, ['upload', 'list', 'file'], true) ? $base : '';
}

function jsonFail(int $status, string $message): void
{
    http_response_code($status);
    echo json_encode(['ok' => false, 'error' => $message]);
    exit;
}

/**
 * @return array{name:string,tmp:string,error:int}
 */
function uploadEntry(array $info, int $i): array
{
    return [
        'name' => is_array($info['name']) ? (string) $info['name'][$i] : (string) $info['name'],
        'tmp' => is_array($info['tmp_name']) ? (string) $info['tmp_name'][$i] : (string) $info['tmp_name'],
        'error' => is_array($info['error']) ? (int) $info['error'][$i] : (int) $info['error'],
    ];
}

/**
 * @return array<string,mixed>
 */
function storeUpload(string $incomingDir, array $upload): array
{
    $originalName = $upload['name'];
    $tmp = $upload['tmp'];
    if ($upload['error'] !== UPLOAD_ERR_OK || $tmp === '' || !is_uploaded_file($tmp)) {
        return ['ok' => false, 'name' => $originalName, 'error' => 'upload error ' . $upload['error']];
    }

    $base = (string) pathinfo($originalName, PATHINFO_FILENAME);
    $ext = (string) pathinfo($originalName, PATHINFO_EXTENSION);
    $base = trim((string) preg_replace('/[^A-Za-z0-9._-]+/', '_', $base), '_');
    $base = (string) preg_replace('/\.{2,}/', '_', $base);
    $base = trim($base, '._');
    if ($base === '' || $base === '_') {
        $base = 'image_' . date('Ymd_His');
        $ext = $ext !== '' ? $ext : 'png';
    }
    $base = substr($base, 0, 64);
    $ext = (string) preg_replace('/[^A-Za-z0-9]/', '', $ext);
    $ext = $ext !== '' ? '.' . strtolower(substr($ext, 0, 12)) : '';

    $candidate = $base . $ext;
    $n = 2;
    while (file_exists($incomingDir . '/' . $candidate)) {
        $candidate = $base . '-' . $n . $ext;
        $n++;
        if ($n > 999) {
            $candidate = $base . '-' . time() . $ext;
            break;
        }
    }

    if (str_contains($candidate, '..') || str_contains($candidate, '/') || str_contains($candidate, chr(0))) {
        return ['ok' => false, 'name' => $originalName, 'error' => 'invalid file name'];
    }

    $target = $incomingDir . '/' . $candidate;
    if (!move_uploaded_file($tmp, $target)) {
        return ['ok' => false, 'name' => $originalName, 'error' => 'could not move file'];
    }

    $realFile = realpath($target);
    if ($realFile === false || !str_starts_with($realFile, (string) realpath($incomingDir) . DIRECTORY_SEPARATOR)) {
        @unlink($target);
        return ['ok' => false, 'name' => $originalName, 'error' => 'invalid target path'];
    }

    @chmod($target, 0666);

    return [
        'ok' => true,
        'name' => $candidate,
        'path' => 'incoming/' . $candidate,
        'size' => (int) filesize($target),
    ];
}

function ensureIncomingDir(string $incomingDir): void
{
    if (!is_dir($incomingDir)) {
        @mkdir($incomingDir, 0777, true);
    }
    if (!is_dir($incomingDir) || !is_writable($incomingDir)) {
        jsonFail(500, 'Cannot create or write ' . $incomingDir);
    }
}

$action = requestAction();
if ($action === '') {
    jsonFail(404, 'Unknown endpoint.');
}

if ($action === 'upload') {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        jsonFail(405, 'Method not allowed. Use POST.');
    }
    ensureIncomingDir($incomingDir);

    $files = [];
    if (isset($_FILES['file'])) {
        $info = $_FILES['file'];
        $count = is_array($info['name']) ? count($info['name']) : 1;
        for ($i = 0; $i < $count; $i++) {
            $files[] = storeUpload($incomingDir, uploadEntry($info, $i));
        }
    }

    echo json_encode(['ok' => true, 'files' => $files]);
    exit;
}

if ($action === 'list') {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
        jsonFail(405, 'Method not allowed. Use GET.');
    }
    $items = [];
    if (is_dir($incomingDir)) {
        foreach (scandir($incomingDir) ?: [] as $entry) {
            if ($entry === '.' || $entry === '..') {
                continue;
            }
            $path = $incomingDir . '/' . $entry;
            if (!is_file($path)) {
                continue;
            }
            $items[] = [
                'name' => $entry,
                'path' => 'incoming/' . $entry,
                'size' => (int) filesize($path),
                'mtime' => (int) filemtime($path),
            ];
        }
        usort($items, static function (array $a, array $b): int {
            return $b['mtime'] <=> $a['mtime'];
        });
    }
    echo json_encode(['ok' => true, 'files' => $items]);
    exit;
}

// $action === 'file': stream a stored upload (inline preview for known types)
$name = basename((string) ($_GET['name'] ?? ''));
if ($name === '' || $name === '.' || $name === '..') {
    jsonFail(400, 'Invalid file name.');
}
$path = $incomingDir . '/' . $name;
if (!is_file($path) || !is_readable($path)) {
    jsonFail(404, 'File not found.');
}

$mimeTypes = [
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'avif' => 'image/avif',
    'bmp' => 'image/bmp',
    'txt' => 'text/plain',
    'md' => 'text/plain',
    'csv' => 'text/csv',
    'mp4' => 'video/mp4',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'zip' => 'application/zip',
];
$inlineTypes = ['pdf', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'avif', 'bmp', 'txt', 'md', 'csv', 'mp4', 'webm', 'mp3', 'wav', 'ogg', 'm4a'];
$ext = strtolower((string) pathinfo($name, PATHINFO_EXTENSION));
$mime = $mimeTypes[$ext] ?? 'application/octet-stream';

header('Content-Type: ' . $mime);
header('Content-Length: ' . (string) filesize($path));
header('X-Content-Type-Options: nosniff');
header('Content-Disposition: ' . (in_array($ext, $inlineTypes, true) ? 'inline' : 'attachment') . '; filename="' . rawurlencode($name) . '"');
readfile($path);
exit;
