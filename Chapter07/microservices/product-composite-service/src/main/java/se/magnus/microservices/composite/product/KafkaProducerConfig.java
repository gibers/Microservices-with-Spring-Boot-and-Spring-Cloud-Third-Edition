package se.magnus.microservices.composite.product;

import java.util.HashMap;
import java.util.Map;

import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.IntegerSerializer;
import org.springframework.boot.autoconfigure.kafka.KafkaProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.support.serializer.JsonSerializer;
import se.magnus.api.event.Event;

@Configuration
public class KafkaProducerConfig {


  private final KafkaProperties kafkaDefaultProperties;

  public KafkaProducerConfig(KafkaProperties kafkaDefaultProperties) {
    this.kafkaDefaultProperties = kafkaDefaultProperties;
  }

  @Bean
  public ProducerFactory<Integer, Event> producerFactory() {

    Map<String, Object> props = kafkaDefaultProperties.buildProducerProperties(null);

    props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, IntegerSerializer.class);
    props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, JsonSerializer.class);

    return new DefaultKafkaProducerFactory<>(props);
  }

  @Bean
  public KafkaTemplate<Integer, Event> kafkaTemplate() {
    return new KafkaTemplate<>(producerFactory());
  }
}
