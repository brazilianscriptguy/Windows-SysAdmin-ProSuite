// File: public/index.php
<?php
session_start();

if (isset($_SERVER['REMOTE_USER'])) {
    $_SESSION['user'] = $_SERVER['REMOTE_USER'];
    header('Location: dashboard.php');
    exit;
}

// If SSO not detected, redirect to manual login
header('Location: login.php');
exit;
?>

---

// File: public/login.php
<?php
require_once __DIR__ . '/../config/ldap.php';
session_start();

$message = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';

    $ldap = new LDAPAuth();
    $auth = $ldap->authenticate($username, $password);

    if ($auth['success']) {
        $_SESSION['user'] = $auth['user_data']['matricula'];
        $_SESSION['name'] = $auth['user_data']['nome'];
        $_SESSION['email'] = $auth['user_data']['email'];
        header('Location: dashboard.php');
        exit;
    } else {
        $message = $auth['message'] ?? 'Login failed';
    }
}
?>
<!DOCTYPE html>
<html>
<head><title>Login</title></head>
<body>
<h2>Manual Login</h2>
<form method="POST">
    <label for="username">Username:</label>
    <input type="text" name="username" required><br>
    <label for="password">Password:</label>
    <input type="password" name="password" required><br>
    <button type="submit">Login</button>
</form>
<p style="color:red;"><?= htmlspecialchars($message) ?></p>
</body>
</html>

---

// File: public/dashboard.php
<?php
session_start();
if (!isset($_SESSION['user'])) {
    header('Location: login.php');
    exit;
}
?>
<!DOCTYPE html>
<html>
<head><title>Dashboard</title></head>
<body>
<h1>Welcome, <?= htmlspecialchars($_SESSION['name'] ?? $_SESSION['user']) ?></h1>
<p>Email: <?= htmlspecialchars($_SESSION['email'] ?? 'N/A') ?></p>
<a href="logout.php">Logout</a>
</body>
</html>

---

// File: public/logout.php
<?php
session_start();
session_destroy();
header('Location: login.php');
exit;
?>
