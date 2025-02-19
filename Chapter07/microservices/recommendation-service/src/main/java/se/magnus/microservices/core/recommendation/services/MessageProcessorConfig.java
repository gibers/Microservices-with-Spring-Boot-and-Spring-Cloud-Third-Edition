package se.magnus.microservices.core.recommendation.services;

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
import se.magnus.api.core.recommendation.Recommendation;
import se.magnus.api.core.recommendation.RecommendationService;
import se.magnus.api.event.Event;
import se.magnus.api.exceptions.EventProcessingException;

@Configuration
public class MessageProcessorConfig {

  private static final Logger LOG = LoggerFactory.getLogger(MessageProcessorConfig.class);
  private static final TypeReference<Event<Integer, Recommendation>> TYPE_REF = new TypeReference<>() {};

  private final RecommendationService recommendationService;
  private final ObjectMapper mapper;

  @Autowired
  public MessageProcessorConfig(RecommendationService recommendationService, ObjectMapper mapper) {
    this.recommendationService = recommendationService;
    this.mapper = mapper;
  }

  @Bean
  public Consumer<Event<Integer, Recommendation>> messageProcessor() {
    return this::messageProcessor;
  }

  @KafkaListener(topics = "recommendations")
  public void messageProcessorString(String eventString) throws JacksonException {
    LOG.info("Process message string {}...", eventString);
    Event<Integer, Recommendation> event = mapper.readValue(eventString, TYPE_REF);
    messageProcessor(event);
  }

  // @KafkaListener(topics = "recommendations")
  public void messageProcessor(Event<Integer, Recommendation> event) {

    LOG.info("Process message created at {}...", event.getEventCreatedAt());

    switch (event.getEventType()) {

      case CREATE:
        Recommendation recommendation = event.getData();
        LOG.info("Create recommendation with ID: {}/{}", recommendation.getProductId(), recommendation.getRecommendationId());
        recommendationService.createRecommendation(recommendation).block();
        break;

      case DELETE:
        int productId = event.getKey();
        LOG.info("Delete recommendations with ProductID: {}", productId);
        recommendationService.deleteRecommendations(productId).block();
        break;

      default:
        String errorMessage = "Incorrect event type: " + event.getEventType() + ", expected a CREATE or DELETE event";
        LOG.warn(errorMessage);
        throw new EventProcessingException(errorMessage);
    }

    LOG.info("Message processing done!");
  }
}
