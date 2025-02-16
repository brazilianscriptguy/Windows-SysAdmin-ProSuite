const express = require("express");
const router = express.Router();
const authenticate = require("../middleware/ldapAuthMiddleware");
const { getUser } = require("../controllers/userController");

router.get("/:username", authenticate, getUser);

module.exports = router;
