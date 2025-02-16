using Microsoft.AspNetCore.Mvc;
using DotNetSSO.API.Services;

namespace DotNetSSO.API.Controllers
{
    [ApiController]
    [Route("api/auth")]
    public class AuthController : ControllerBase
    {
        private readonly LdapService _ldapService;

        public AuthController(LdapService ldapService)
        {
            _ldapService = ldapService;
        }

        [HttpPost("login")]
        public IActionResult Login([FromBody] LoginRequest request)
        {
            var isAuthenticated = _ldapService.AuthenticateUser(request.Username, request.Password);
            if (!isAuthenticated)
            {
                return Unauthorized();
            }
            return Ok(new { Message = "Authentication successful" });
        }
    }

    public class LoginRequest
    {
        public string Username { get; set; }
        public string Password { get; set; }
    }
}
