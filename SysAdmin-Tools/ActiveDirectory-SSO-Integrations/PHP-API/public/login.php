<?php
// File: public/login.php
session_start();
require_once __DIR__ . '/../config/ldap.php';

$message = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $logincode = $_POST['logincode'] ?? '';
    $password     = $_POST['password'] ?? '';

    $ldap = new LDAPAuth();
    $result = $ldap->authenticate($logincode, $password);

    if ($result['success']) {
        $_SESSION['user'] = $result['user_data']['logincode'];
        $_SESSION['name'] = $result['user_data']['nome'];
        $_SESSION['email'] = $result['user_data']['email'];
        header('Location: dashboard.php');
        exit;
    } else {
        $message = $result['message'];
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Login</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
</head>
<body class="container mt-5">
    <h2>Manual Login</h2>
    <?php if (!empty($message)): ?>
        <div class="alert alert-danger"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <form method="POST">
        <div class="mb-3">
            <label for="logincode" class="form-label">Username / logincode</label>
            <input type="text" class="form-control" id="logincode" name="logincode" required>
        </div>
        <div class="mb-3">
            <label for="password" class="form-label">Password</label>
            <input type="password" class="form-control" id="password" name="password" required>
        </div>
        <button type="submit" class="btn btn-primary">Log In</button>
    </form>
</body>
</html>
