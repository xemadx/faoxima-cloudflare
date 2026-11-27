<?php

declare(strict_types=1);

$rootDirectory = '/mnt/faoxima/app';
define('RX_INSTALLER_RUNNING', true);
define('REFACTORED_LEGACY_ROOT', $rootDirectory);
chdir($rootDirectory);
require '/opt/cloudflare/installer/helpers.php';

for ($attempt = 0; $attempt < 2; $attempt++) {
    $result = rx_execute_table_file($rootDirectory . '/table.php');
    if ($result['ok'] && ($pdo ?? null) instanceof PDO && rx_table_migrations_verify_ready([], $diagnostics, $pdo)) {
        $admin = rx_ensure_admin_record([], (string) getenv('TELEGRAM_ADMIN_ID'), $pdo);
        if ($admin['ok']) {
            fwrite(STDOUT, "Faoxima database schema and administrator verified.\n");
            exit(0);
        }
    }
}

fwrite(STDERR, "Faoxima database migration failed. Check the application schema, grants and database TLS settings.\n");
exit(1);
