const passport = require("passport");

const authenticate = (req, res, next) => {
  passport.authenticate("ldapauth", { session: false }, (err, user, info) => {
    if (err || !user) {
      return res.status(401).json({ message: "Authentication failed", error: info });
    }
    req.user = user;
    next();
  })(req, res, next);
};

module.exports = authenticate;
