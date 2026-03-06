<?php

declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

session_start([
    'cookie_secure'   => isset($_SERVER['HTTPS']),
    'cookie_httponly' => true,
    'cookie_samesite' => 'Strict',
]);

if (empty($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}

$user = $_SESSION['user'];
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; }
        .card { border: 1px solid #ddd; padding: 20px; border-radius: 8px; }
        a { color: #1976d2; text-decoration: none; }
        a:hover { text-decoration: underline; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Bem-vindo, <?= htmlspecialchars($user['name'] ?: $user['username']) ?></h1>
        
        <p><strong>Usuário:</strong> <?= htmlspecialchars($user['username']) ?></p>
        <p><strong>E-mail:</strong> <?= htmlspecialchars($user['email'] ?: 'Não informado') ?></p>
        
        <p><a href="logout.php">Sair (Logout)</a></p>
    </div>
</body>
</html>
