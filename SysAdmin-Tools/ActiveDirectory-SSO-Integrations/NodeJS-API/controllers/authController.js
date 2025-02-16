const login = (req, res) => {
  res.json({ message: "Authentication successful", user: req.user });
};

module.exports = { login };
