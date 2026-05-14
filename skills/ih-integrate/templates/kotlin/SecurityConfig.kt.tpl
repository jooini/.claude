// src/main/kotlin/${BASE_PKG_PATH}/security/SecurityConfig.kt
// build.gradle.kts:
//   implementation("org.springframework.boot:spring-boot-starter-oauth2-resource-server")
package ${BASE_PKG}.security

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.web.SecurityFilterChain

@Configuration
@EnableWebSecurity
class SecurityConfig {
    @Bean
    fun filterChain(http: HttpSecurity): SecurityFilterChain {
        http.authorizeHttpRequests {
            it.requestMatchers("/public/**", "/health", "/api/auth/**").permitAll()
              .anyRequest().authenticated()
        }
        http.oauth2ResourceServer { it.jwt { } }
        return http.build()
    }
}
