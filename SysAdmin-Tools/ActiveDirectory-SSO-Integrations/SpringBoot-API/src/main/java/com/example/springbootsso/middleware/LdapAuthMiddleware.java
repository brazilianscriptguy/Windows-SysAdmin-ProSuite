package com.example.springbootsso.middleware;

import com.example.springbootsso.services.LdapService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.util.WebUtils;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.Base64;

/**
 * Middleware for enforcing authentication using LDAP.
 */
@Component
public class LdapAuthMiddleware implements HandlerInterceptor {

    private final LdapService ldapService;

    public LdapAuthMiddleware(LdapService ldapService) {
        this.ldapService = ldapService;
    }

    /**
     * Pre-handle method to enforce authentication before processing the request.
     *
     * @param request  The HTTP request.
     * @param response The HTTP response.
     * @param handler  The handler object.
     * @return true if authentication succeeds, false otherwise.
     */
    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        String authHeader = request.getHeader(HttpHeaders.AUTHORIZATION);

        if (authHeader == null || !authHeader.startsWith("Basic ")) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            response.setHeader("WWW-Authenticate", "Basic realm=\"LDAP Authentication\"");
            return false;
        }

        // Extract and decode credentials
        String base64Credentials = authHeader.substring("Basic ".length());
        String credentials = new String(Base64.getDecoder().decode(base64Credentials));
        String[] values = credentials.split(":", 2);

        if (values.length != 2) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            return false;
        }

        String username = values[0];
        String password = values[1];

        // Validate against LDAP
        boolean isAuthenticated = ldapService.authenticate(username, password);
        if (!isAuthenticated) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            return false;
        }

        return true;
    }
}
