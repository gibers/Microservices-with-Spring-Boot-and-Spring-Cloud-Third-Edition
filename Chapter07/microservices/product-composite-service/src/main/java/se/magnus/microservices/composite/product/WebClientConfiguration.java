package se.magnus.microservices.composite.product;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.function.client.WebClient;

@Configuration(proxyBeanMethods = false)
class WebClientConfiguration {

  private static final Logger LOG = LoggerFactory.getLogger(WebClientConfiguration.class);

  @Bean
  WebClient webClient(WebClient.Builder builder) {
    LOG.info("Creates a WebClient bean");
    return builder.build();
  }

}
