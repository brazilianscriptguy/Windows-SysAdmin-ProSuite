const express = require('express');
const bodyParser = require('body-parser');
const passport = require('passport');
const LdapStrategy = require('passport-ldapauth');
const fs = require('fs');
const app = express();

// Load LDAP configuration from file
let ldapConfig = JSON.parse(fs.readFileSync('./config/ldap.config.json', 'utf8'));

// Replace placeholder with the actual environment variable value
ldapConfig.server.bindCredentials = process.env.LDAP_PASSWORD || 'your_generic_password';

passport.use(new LdapStrategy(ldapConfig));

app.use(bodyParser.json());
app.use(passport.initialize());

// Example login endpoint
app.post('/login', passport.authenticate('ldapauth', { session: false }), (req, res) => {
  res.json({ message: 'Authenticated successfully!', user: req.user });
});

app.listen(3000, () => {
  console.log('NodeJS SSO API is running on port 3000');
});
