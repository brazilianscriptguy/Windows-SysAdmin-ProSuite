<?php
// Path: config/env.php
// Load .env file into environment variables safely and consistently

function loadEnv($file = __DIR__ . '/../.env') {
    if (!file_exists($file)) {
        trigger_error("Environment file not found: {$file}", E_USER_WARNING);
        return;
    }

    $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) continue;

        // Remove UTF-8 BOM if present
        if (substr($line, 0, 3) === "\xEF\xBB\xBF") {
            $line = substr($line, 3);
        }

        if (!str_contains($line, '=')) continue;

        [$key, $value] = explode('=', $line, 2);
        $key = trim($key);
        $value = trim($value);

        if (!isset($_ENV[$key]) && !isset($_SERVER[$key])) {
            putenv("{$key}={$value}");
            $_ENV[$key] = $value;
            $_SERVER[$key] = $value;
        }
    }
}

// Automatically load when included
loadEnv();
