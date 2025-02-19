package se.magnus.microservices.core.review.services;

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
import se.magnus.api.core.review.Review;
import se.magnus.api.core.review.ReviewService;
import se.magnus.api.event.Event;
import se.magnus.api.exceptions.EventProcessingException;

@Configuration
public class MessageProcessorConfig {

  private static final Logger LOG = LoggerFactory.getLogger(MessageProcessorConfig.class);
  private static final TypeReference<Event<Integer, Review>> TYPE_REF = new TypeReference<>() {};

  private final ReviewService reviewService;
  private final ObjectMapper mapper;

  @Autowired
  public MessageProcessorConfig(ReviewService reviewService, ObjectMapper mapper) {
    this.reviewService = reviewService;
    this.mapper = mapper;
  }

  @Bean
  public Consumer<Event<Integer, Review>> messageProcessor() {
    return this::messageProcessor;
  }

  @KafkaListener(topics = "reviews")
  public void messageProcessorString(String eventString) throws JacksonException {
    LOG.info("Process message string {}...", eventString);
    Event<Integer, Review> event = mapper.readValue(eventString, TYPE_REF);
    messageProcessor(event);
  }

  // @KafkaListener(topics = "reviews")
  public void messageProcessor(Event<Integer, Review> event) {

    LOG.info("Process message created at {}...", event.getEventCreatedAt());

    switch (event.getEventType()) {

      case CREATE:
        Review review = event.getData();
        LOG.info("Create review with ID: {}/{}", review.getProductId(), review.getReviewId());
        reviewService.createReview(review).block();
        break;

      case DELETE:
        int productId = event.getKey();
        LOG.info("Delete reviews with ProductID: {}", productId);
        reviewService.deleteReviews(productId).block();
        break;

      default:
        String errorMessage = "Incorrect event type: " + event.getEventType() + ", expected a CREATE or DELETE event";
        LOG.warn(errorMessage);
        throw new EventProcessingException(errorMessage);
    }

    LOG.info("Message processing done!");
  }
}
