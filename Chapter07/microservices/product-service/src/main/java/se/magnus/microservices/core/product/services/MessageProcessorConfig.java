package se.magnus.microservices.core.product.services;

import java.util.function.Consumer;

import com.fasterxml.jackson.core.JacksonException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.KafkaListener;
import se.magnus.api.core.product.Product;
import se.magnus.api.core.product.ProductService;
import se.magnus.api.event.Event;
import se.magnus.api.exceptions.EventProcessingException;

@Configuration
public class MessageProcessorConfig {

  private static final Logger LOG = LoggerFactory.getLogger(MessageProcessorConfig.class);

  private static final TypeReference<Event<Integer, Product>> TYPE_REF = new TypeReference<>() {};

  private final ProductService productService;
  private final ObjectMapper mapper;

  @Autowired
  public MessageProcessorConfig(ProductService productService, ObjectMapper mapper) {
    this.productService = productService;
    this.mapper = mapper;
  }

  @Bean
  public Consumer<Event<Integer, Product>> messageProcessor() {
    return this::messageProcessor;
  }

  @KafkaListener(topics = "products")
  public void messageProcessorString(String eventString) throws JacksonException {
    LOG.info("Process message string {}...", eventString);
    Event<Integer, Product> event = mapper.readValue(eventString, TYPE_REF);
    messageProcessor(event);
  }

  // @KafkaListener(topics = "products")
  public void messageProcessor(Event<Integer, Product> event) {

    // Try with string and convert by code, see https://stackoverflow.com/questions/70295975/class-java-util-linkedhashmap-cannot-be-cast-to-class

    LOG.info("Process message created at {}...", event.getEventCreatedAt());

    switch (event.getEventType()) {

      case CREATE:
        Product product = event.getData();
        LOG.info("Create product with ID: {}", product.getProductId());
        productService.createProduct(product).block();
        break;

      case DELETE:
        int productId = event.getKey();
        LOG.info("Delete product with ProductID: {}", productId);
        productService.deleteProduct(productId).block();
        break;

      default:
        String errorMessage = "Incorrect event type: " + event.getEventType() + ", expected a CREATE or DELETE event";
        LOG.warn(errorMessage);
        throw new EventProcessingException(errorMessage);
    }

    LOG.info("Message processing done!");
  }
}
