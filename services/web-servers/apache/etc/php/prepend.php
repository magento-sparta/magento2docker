<?php

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

$docRoot = rtrim($apacheRoot, '/') . '/' . $segments[0];

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
        'php_version' => 'php' . $m[1] . '.' . $m[2], //to be used for dynamic php
        'sql_version' => '',
        'search_engine' => '',
        'cache_engine' => '' //redis, valkey
    ])
);
