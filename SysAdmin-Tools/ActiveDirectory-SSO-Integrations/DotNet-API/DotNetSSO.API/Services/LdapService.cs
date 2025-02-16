using System;
using Novell.Directory.Ldap;

namespace DotNetSSO.API.Services
{
    public class LdapService
    {
        private readonly string _ldapServer;
        private readonly string _baseDn;
        private readonly string _bindDn;
        private readonly string _bindPassword;
        private readonly string _userFilter;

        public LdapService()
        {
            _ldapServer = "ldap://ldap.headq.scriptguy:3268";
            _baseDn = "dc=headq,dc=scriptguy";
            _bindDn = "cn=ad-sso-authentication,ou=ServiceAccounts,dc=headq,dc=scriptguy";
            _bindPassword = "REPLACE_WITH_ENV_VAR";
            _userFilter = "(sAMAccountName={0})";
        }

        public bool AuthenticateUser(string username, string password)
        {
            try
            {
                using (var conn = new LdapConnection())
                {
                    conn.Connect(_ldapServer, 3268);
                    conn.Bind(_bindDn, _bindPassword);

                    var searchFilter = string.Format(_userFilter, username);
                    var searchResults = conn.Search(_baseDn, LdapConnection.SCOPE_SUB, searchFilter, null, false);

                    if (searchResults.HasMore())
                    {
                        var user = searchResults.Next();
                        var userDn = user.DN;
                        conn.Bind(userDn, password);
                        return conn.Bound;
                    }
                }
            }
            catch (Exception)
            {
                return false;
            }
            return false;
        }
    }
}
