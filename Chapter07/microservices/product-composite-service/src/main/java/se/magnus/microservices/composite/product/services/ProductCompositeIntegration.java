package se.magnus.microservices.composite.product.services;

import static java.util.logging.Level.FINE;
import static reactor.core.publisher.Flux.empty;
import static se.magnus.api.event.Event.Type.CREATE;
import static se.magnus.api.event.Event.Type.DELETE;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.health.Health;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.http.HttpStatus;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.messaging.Message;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.stereotype.Component;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Scheduler;
import se.magnus.api.core.product.Product;
import se.magnus.api.core.product.ProductService;
import se.magnus.api.core.recommendation.Recommendation;
import se.magnus.api.core.recommendation.RecommendationService;
import se.magnus.api.core.review.Review;
import se.magnus.api.core.review.ReviewService;
import se.magnus.api.event.Event;
import se.magnus.api.exceptions.InvalidInputException;
import se.magnus.api.exceptions.NotFoundException;
import se.magnus.util.http.HttpErrorInfo;

@RefreshScope
@Component
public class ProductCompositeIntegration implements ProductService, RecommendationService, ReviewService {

  private static final Logger LOG = LoggerFactory.getLogger(ProductCompositeIntegration.class);

  private final WebClient webClient;
  private final ObjectMapper mapper;

  private final String productServiceHost;
  private final String recommendationServiceHost;
  private final String reviewServiceHost;

  private final int productServicePort;
  private final int recommendationServicePort;
  private final int reviewServicePort;

  private final Map<String, String> ipAddressCache = new HashMap<>();

  private final Scheduler publishEventScheduler;

  @Autowired
  public ProductCompositeIntegration(
    @Qualifier("publishEventScheduler") Scheduler publishEventScheduler,

    WebClient webClient,
    ObjectMapper mapper,

    @Value("${app.product-service.host}") String productServiceHost,
    @Value("${app.product-service.port}") int  productServicePort,

    @Value("${app.recommendation-service.host}") String recommendationServiceHost,
    @Value("${app.recommendation-service.port}") int  recommendationServicePort,

    @Value("${app.review-service.host}") String reviewServiceHost,
    @Value("${app.review-service.port}") int  reviewServicePort
  ) {

    this.publishEventScheduler = publishEventScheduler;
    this.webClient = webClient;
    this.mapper = mapper;

    this.productServiceHost = productServiceHost;
    this.recommendationServiceHost = recommendationServiceHost;
    this.reviewServiceHost = reviewServiceHost;

    this.productServicePort = productServicePort;
    this.recommendationServicePort = recommendationServicePort;
    this.reviewServicePort = reviewServicePort;
  }

  @Override
  public Mono<Product> createProduct(Product body) {

    return Mono.fromCallable(() -> {
      sendMessage("products", new Event(CREATE, body.getProductId(), body));
      return body;
    }).subscribeOn(publishEventScheduler);
  }

  @Override
  public Mono<Product> getProduct(int productId) {
    LOG.debug("Will call the getProduct API on URL http://{}:{}{}", productServiceHost, productServicePort, "/product/" + productId);
    return createRequest(productServiceHost, productServicePort, "/product/" + productId).retrieve().bodyToMono(Product.class).log(LOG.getName(), FINE).onErrorMap(WebClientResponseException.class, ex -> handleException(ex));
  }

  @Override
  public Mono<Void> deleteProduct(int productId) {

    return Mono.fromRunnable(() -> sendMessage("products", new Event(DELETE, productId, null)))
      .subscribeOn(publishEventScheduler).then();
  }

  @Override
  public Mono<Recommendation> createRecommendation(Recommendation body) {

    return Mono.fromCallable(() -> {
      sendMessage("recommendations", new Event(CREATE, body.getProductId(), body));
      return body;
    }).subscribeOn(publishEventScheduler);
  }

  @Override
  public Flux<Recommendation> getRecommendations(int productId) {

    LOG.debug("Will call the getRecommendations API on URL http://{}:{}{}", recommendationServiceHost, recommendationServicePort, "/recommendation?productId=" + productId);

    // Return an empty result if something goes wrong to make it possible for the composite service to return partial responses
    return createRequest(recommendationServiceHost, recommendationServicePort,"/recommendation?productId=" + productId ).retrieve().bodyToFlux(Recommendation.class).log(LOG.getName(), FINE).onErrorResume(error -> empty());
  }

  @Override
  public Mono<Void> deleteRecommendations(int productId) {

    return Mono.fromRunnable(() -> sendMessage("recommendations", new Event(DELETE, productId, null)))
      .subscribeOn(publishEventScheduler).then();
  }

  @Override
  public Mono<Review> createReview(Review body) {

    return Mono.fromCallable(() -> {
      sendMessage("reviews", new Event(CREATE, body.getProductId(), body));
      return body;
    }).subscribeOn(publishEventScheduler);
  }

  @Override
  public Flux<Review> getReviews(int productId) {

    LOG.debug("Will call the getReviews API on URL http://{}:{}{}", reviewServiceHost, reviewServicePort, "/review?productId=" + productId);

    // Return an empty result if something goes wrong to make it possible for the composite service to return partial responses
    return createRequest(reviewServiceHost, reviewServicePort, "/review?productId=" + productId).retrieve().bodyToFlux(Review.class).log(LOG.getName(), FINE).onErrorResume(error -> empty());
  }

  @Override
  public Mono<Void> deleteReviews(int productId) {

    return Mono.fromRunnable(() -> sendMessage("reviews", new Event(DELETE, productId, null)))
      .subscribeOn(publishEventScheduler).then();
  }

  public Mono<Health> getProductHealth() {
    return getHealth(productServiceHost, productServicePort);
  }

  public Mono<Health> getRecommendationHealth() {
    return getHealth(recommendationServiceHost, recommendationServicePort);
  }

  public Mono<Health> getReviewHealth() {
    return getHealth(reviewServiceHost, reviewServicePort);
  }

  private Mono<Health> getHealth(String hostName, int port) {

    LOG.debug("Will call the Health API on URL http://{}:{}{}", hostName, port, "/actuator/health");

    return createRequest(hostName, port, "/actuator/health").retrieve().bodyToMono(String.class)
      .map(s -> new Health.Builder().up().build())
      .onErrorResume(ex -> Mono.just(new Health.Builder().down(ex).build()))
      .log(LOG.getName(), FINE);
  }

  private WebClient.RequestHeadersSpec<?> createRequest(String hostName, int port, String uri) {
    // Workaround for Netty Web Client that sometimes (unsure when...) takes 4 min to resolve a hostname in Docker after being restored from a CRaC checkpoint
    // String url = "http://" + getIpAddress(hostName) + ":" + port + uri;
    // return webClient.get().uri(url).header("Host", hostName);
    return webClient.get().uri("http://" + hostName + ":" + port + uri);
  }

  // Workaround for Netty Web Client...
  private String getIpAddress(String hostname) {
    if (!ipAddressCache.containsKey(hostname)) {
      ipAddressCache.put(hostname, resolveIpAddress(hostname));
    }
    return ipAddressCache.get(hostname);
  }

  // Workaround for Netty Web Client...
  private String resolveIpAddress(String hostname) {
    try {
      var ipAddress = InetAddress.getByName(hostname).getHostAddress();
      LOG.info("Resolving hostname {} to IP address {}", hostname, ipAddress);
      return ipAddress;
    } catch (UnknownHostException e) {
      throw new RuntimeException(e);
    }
  }

  @Autowired
  private KafkaTemplate<Integer, Event> kafkaTemplate;

  private void sendMessage(String topic, Event event) {
    LOG.debug("Sending a {} message to {}", event.getEventType(), topic);
    Message message = MessageBuilder.withPayload(event)
      .setHeader("partitionKey", event.getKey())
      .build();
    publishOnKafkaTopic(topic, event);
  }

  public void publishOnKafkaTopic(String topic, Event<Integer, Object> event) {
    // TODO: Use join() to wait for the future to complete
    // TODO: Or map CompletableFuture to Mono and return it
    CompletableFuture<SendResult<Integer, Event>> future = kafkaTemplate.send(topic, event.getKey(), event);
    future.whenComplete((result, ex) -> {
      if (ex == null) {
        LOG.info("### Sent message with key=[{}] with offset=[{}]", event.getKey(), result.getRecordMetadata().offset());
      } else {
        LOG.warn("### Unable to send message with key=[{}] due to : {}", event.getKey(), ex.getMessage());
      }
    });
  }

  private Throwable handleException(Throwable ex) {

    if (!(ex instanceof WebClientResponseException)) {
      LOG.warn("Got a unexpected error: {}, will rethrow it", ex.toString());
      return ex;
    }

    WebClientResponseException wcre = (WebClientResponseException)ex;

    switch (HttpStatus.resolve(wcre.getStatusCode().value())) {

      case NOT_FOUND:
        return new NotFoundException(getErrorMessage(wcre));

      case UNPROCESSABLE_ENTITY:
        return new InvalidInputException(getErrorMessage(wcre));

      default:
        LOG.warn("Got an unexpected HTTP error: {}, will rethrow it", wcre.getStatusCode());
        LOG.warn("Error body: {}", wcre.getResponseBodyAsString());
        return ex;
    }
  }

  private String getErrorMessage(WebClientResponseException ex) {
    try {
      return mapper.readValue(ex.getResponseBodyAsString(), HttpErrorInfo.class).getMessage();
    } catch (IOException ioex) {
      return ex.getMessage();
    }
  }
}
