package com.example.springbootsso;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.springbootsso.controllers.AuthController;
import com.example.springbootsso.controllers.UserController;
import com.example.springbootsso.services.LdapService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Unit test for Spring Boot SSO API
 */
@SpringBootTest
@ActiveProfiles("test")
public class SpringBootSsoApplicationTests {

    @Autowired
    private AuthController authController;

    @Autowired
    private UserController userController;

    @Autowired
    private LdapService ldapService;

    /**
     * Test if the Spring context loads properly.
     */
    @Test
    public void contextLoads() {
        assertThat(authController).isNotNull();
        assertThat(userController).isNotNull();
        assertThat(ldapService).isNotNull();
    }

    /**
     * Test authentication with LDAP
     */
    @Test
    public void testAuthentication() {
        String username = "test.user";
        String password = "SuperSecretPassword";
        boolean isAuthenticated = ldapService.authenticate(username, password);

        assertThat(isAuthenticated).isTrue();
    }
}
