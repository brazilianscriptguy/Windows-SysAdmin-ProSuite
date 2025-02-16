using Microsoft.AspNetCore.Mvc;

namespace DotNetSSO.API.Controllers
{
    [ApiController]
    [Route("api/user")]
    public class UserController : ControllerBase
    {
        [HttpGet("{username}")]
        public IActionResult GetUser(string username)
        {
            return Ok(new { Username = username, Role = "User" });
        }
    }
}
