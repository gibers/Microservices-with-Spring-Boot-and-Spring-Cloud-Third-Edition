package se.magnus.microservices.composite.product;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.ReactorNettyClientRequestFactory;
import org.springframework.http.client.reactive.ReactorResourceFactory;
import org.springframework.web.client.RestTemplate;

@Configuration(proxyBeanMethods = false)
class RestTemplateConfiguration {

  private static final Logger LOG = LoggerFactory.getLogger(RestTemplateConfiguration.class);

  @Bean
  RestTemplate restTemplate(RestTemplateBuilder builder, ClientHttpRequestFactory requestFactory) {
    LOG.info("### Creating a RestTemplate bean based on a RequestFactory: {}", requestFactory.getClass().getName());
    return builder.defaultHeader("User-Agent", "RestTemplateApplication")
      .requestFactory(() -> requestFactory)
      .build();
  }

  @Bean
  ReactorResourceFactory resourceFactory() {
    return new ReactorResourceFactory();
  }

  @Bean
  ClientHttpRequestFactory requestFactory(ReactorResourceFactory resourceFactory) {
    return new ReactorNettyClientRequestFactory(resourceFactory, mapper -> mapper.compress(true));
  }

}
