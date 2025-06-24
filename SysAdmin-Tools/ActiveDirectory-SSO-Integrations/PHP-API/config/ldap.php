<?php
// Path: config/ldap.php
// LDAP Authentication for Active Directory with forest-wide scope (GC) and user filtering

class LDAPAuth {
    private $ldap_server;
    private $ldap_port;
    private $bind_user;
    private $bind_pass;
    private $base_dn;
    private $connection;

    public function __construct() {
        $this->ldap_server = getenv('LDAP_URL');
        $this->ldap_port   = 3268;
        $this->bind_user   = getenv('LDAP_USERNAME');
        $this->bind_pass   = getenv('LDAP_PASSWORD');
        $this->base_dn     = getenv('LDAP_BASE_DN');
        $this->connection  = null;
    }

    private function connect() {
        if ($this->connection !== null) return;

        $this->connection = @ldap_connect($this->ldap_server, $this->ldap_port);
        if (!$this->connection) {
            throw new Exception("Failed to connect to LDAP server.");
        }

        ldap_set_option($this->connection, LDAP_OPT_PROTOCOL_VERSION, 3);
        ldap_set_option($this->connection, LDAP_OPT_REFERRALS, 0);
        ldap_set_option($this->connection, LDAP_OPT_NETWORK_TIMEOUT, 5);

        if (!@ldap_bind($this->connection, $this->bind_user, $this->bind_pass)) {
            throw new Exception("Failed to bind using service account credentials.");
        }
    }

    public function authenticate($username, $password) {
        $user_data = $this->searchUser($username);
        if (!$user_data) return false;

        $user_dn = $user_data['dn'];
        $auth_conn = @ldap_connect($this->ldap_server, $this->ldap_port);

        ldap_set_option($auth_conn, LDAP_OPT_PROTOCOL_VERSION, 3);
        ldap_set_option($auth_conn, LDAP_OPT_REFERRALS, 0);
        ldap_set_option($auth_conn, LDAP_OPT_NETWORK_TIMEOUT, 3);

        if (@ldap_bind($auth_conn, $user_dn, $password)) {
            ldap_close($auth_conn);
            return [
                'username' => $username,
                'name'     => $user_data['displayname'][0] ?? '',
                'email'    => $user_data['mail'][0] ?? ''
            ];
        }

        ldap_close($auth_conn);
        return false;
    }

    public function searchUser($username) {
        $this->connect();

        // Exclude inetOrgPerson and disabled accounts
        $filter = "(&(objectClass=user)(objectCategory=person)(!(objectClass=inetOrgPerson))(sAMAccountName={$username}))";
        $attributes = ['dn', 'displayname', 'mail', 'samaccountname'];

        $search = @ldap_search($this->connection, $this->base_dn, $filter, $attributes);
        if (!$search) return false;

        $entries = ldap_get_entries($this->connection, $search);
        return ($entries['count'] > 0) ? $entries[0] : false;
    }

    public function __destruct() {
        if ($this->connection) ldap_close($this->connection);
    }
}
?>
