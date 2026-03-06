<?php

declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

use App\Auth\LdapService;

session_start([
    'cookie_secure'   => isset($_SERVER['HTTPS']),
    'cookie_httponly' => true,
    'cookie_samesite' => 'Strict',
]);

if (!empty($_SESSION['user'])) {
    header('Location: dashboard.php');
    exit;
}

// Generate CSRF token
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!isset($_POST['csrf_token']) || $_POST['csrf_token'] !== $_SESSION['csrf_token']) {
        $error = 'Invalid CSRF token.';
    } else {
        $username = trim($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';

        if (empty($username) || empty($password)) {
            $error = 'Both fields are required.';
        } else {
            $ldap = new LdapService();
            $userData = $ldap->authenticate($username, $password);

            if ($userData) {
                $_SESSION['user'] = $userData;
                unset($_SESSION['csrf_token']); // one-time use
                header('Location: dashboard.php');
                exit;
            } else {
                $error = 'Invalid username or password.';
            }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - SSO</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 400px; margin: 80px auto; padding: 20px; }
        .error { color: #d32f2f; }
        form { display: flex; flex-direction: column; gap: 16px; }
        label { display: flex; flex-direction: column; gap: 6px; }
        input { padding: 10px; font-size: 16px; }
        button { padding: 12px; background: #1976d2; color: white; border: none; cursor: pointer; }
        button:hover { background: #1565c0; }
    </style>
</head>
<body>
    <h2>Autenticação Manual</h2>

    <?php if ($error): ?>
        <p class="error"><?= htmlspecialchars($error) ?></p>
    <?php endif; ?>

    <form method="post" action="login.php">
        <input type="hidden" name="csrf_token" value="<?= htmlspecialchars($_SESSION['csrf_token']) ?>">
        
        <label>
            Usuário (ou e-mail):
            <input type="text" name="username" required autofocus>
        </label>

        <label>
            Senha:
            <input type="password" name="password" required>
        </label>

        <button type="submit">Entrar</button>
    </form>
</body>
</html>
