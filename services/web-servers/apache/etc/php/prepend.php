<?php


// ── Project root detection ────────────────────────────────────────────────────

$apacheRoot = getenv('M2D_APACHE_ROOT_DIRECTORY');
if (!$apacheRoot) {
    return;
}

$currentPath = getcwd();
if (strpos($currentPath, $apacheRoot) === false) {
    return;
}

$relative = substr($currentPath, strlen(rtrim($apacheRoot, '/')));
$segments = explode('/', trim($relative, '/'));
if (empty($segments[0])) {
    return;
}

$docRoot        = rtrim($apacheRoot, '/') . '/' . $segments[0];
$projectPrepend = $docRoot . '/prepend.php';

// ── Copy to project root; load project copy in place of global ────────────────
// Running as global (/usr/local/lib/php/prepend.php): copy self once, then
// delegate entirely — the project copy takes over for this request.
// Running as project copy: realpath matches, block is skipped, execution
// continues below to meta.json.

if (realpath($projectPrepend) !== realpath(__FILE__)) {
    if (!file_exists($projectPrepend)) {
        @copy(__FILE__, $projectPrepend);
        @copy(__FILE__, $docRoot . '/prepend.dist.php');
    }
    if (file_exists($projectPrepend)) {
        require $projectPrepend;
        return;
    }
}
unset($projectPrepend);

// ── New Relic ini settings ────────────────────────────────────────────────────
ini_set('newrelic.browser_monitoring.auto_instrument', '1');

// ── New Relic mock configuration ──────────────────────────────────────────────
// This block is only reached by the project-root copy of prepend.php, never
// by the global original — so overrides apply exactly once per request.
//
// Use newrelic_mock_set(string $function, callable $handler) to override any
// stub.  The handler receives the same arguments as the real NR function.
// Use newrelic_mock_reset(?string $function = null) to remove override(s).
//
// ── Examples ─────────────────────────────────────────────────────────────────
//
// Log every named transaction to the PHP error log:
// newrelic_mock_set('newrelic_name_transaction', function (string $name): bool {
//     error_log('[NR] transaction: ' . $name);
//     return true;
// });
//
// Make newrelic_is_sampled() return true (default: false):
// newrelic_mock_set('newrelic_is_sampled', fn (): bool => true);
//
// Suppress browser timing output entirely:
// newrelic_mock_set('newrelic_get_browser_timing_header', fn (): string => '');
// newrelic_mock_set('newrelic_get_browser_timing_footer', fn (): string => '');
//
// Capture custom parameters for debugging:
// newrelic_mock_set('newrelic_add_custom_parameter',
//     function (string $key, mixed $value): bool {
//         error_log('[NR] param: ' . $key . ' = ' . print_r($value, true));
//         return true;
//     }
// );

// ── meta.json creation from phpXX.code.tgz ───────────────────────────────────

$metaFile = $docRoot . '/meta.json';
if (file_exists($metaFile)) {
    return;
}

$tgzFiles = glob($docRoot . '/php[0-9][0-9].code.tgz') ?: [];
if (empty($tgzFiles)) {
    return;
}

$filename = basename($tgzFiles[0]);
if (!preg_match('/^php(\d)(\d)\.code\.tgz$/', $filename, $m)) {
    return;
}

file_put_contents($metaFile,
    json_encode([
        'php_version'   => 'php' . $m[1] . '.' . $m[2],
        'sql_version'   => '',
        'search_engine' => '',
        'cache_engine'  => '',
    ])
);
