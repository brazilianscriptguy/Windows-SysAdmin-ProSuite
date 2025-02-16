require("dotenv").config();
const express = require("express");
const passport = require("passport");
const LdapStrategy = require("passport-ldapauth");
const authRoutes = require("./routes/authRoutes");
const userRoutes = require("./routes/userRoutes");

const app = express();
app.use(express.json());

const ldapOptions = require("./config/ldap.config.json");
passport.use(new LdapStrategy(ldapOptions.server));
app.use(passport.initialize());

// Routes
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`NodeJS-API is running on http://localhost:${PORT}`);
});
