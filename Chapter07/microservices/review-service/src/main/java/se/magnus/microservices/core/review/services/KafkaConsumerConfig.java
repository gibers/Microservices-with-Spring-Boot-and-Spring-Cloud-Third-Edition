package se.magnus.microservices.core.review.services;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.serialization.IntegerDeserializer;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.springframework.boot.autoconfigure.kafka.KafkaProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.EnableKafka;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.core.ConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import se.magnus.api.event.Event;

import java.util.Map;

@EnableKafka
@Configuration
public class KafkaConsumerConfig {

  private final KafkaProperties kafkaDefaultProperties;

  public KafkaConsumerConfig(KafkaProperties kafkaDefaultProperties) {
    this.kafkaDefaultProperties = kafkaDefaultProperties;
  }

  @Bean
  public ConsumerFactory<Integer, Event> consumerFactoryJson() {

    Map<String, Object> props = kafkaDefaultProperties.buildConsumerProperties(null);

    props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, IntegerDeserializer.class);
    props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, JsonDeserializer.class);
    props.put(JsonDeserializer.TRUSTED_PACKAGES, "*");

    return new DefaultKafkaConsumerFactory<>(props);
  }

  @Bean
  public ConcurrentKafkaListenerContainerFactory<Integer, Event> kafkaListenerContainerFactoryJson() {

    ConcurrentKafkaListenerContainerFactory<Integer, Event> factory = new ConcurrentKafkaListenerContainerFactory<>();
    factory.setConsumerFactory(consumerFactoryJson());
    return factory;
  }

  @Bean
  public ConsumerFactory<Integer, String> consumerFactoryString() {

    Map<String, Object> props = kafkaDefaultProperties.buildConsumerProperties(null);

    props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, IntegerDeserializer.class);
    props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);

    return new DefaultKafkaConsumerFactory<>(props);
  }

  @Bean
  public ConcurrentKafkaListenerContainerFactory<Integer, String> kafkaListenerContainerFactoryString() {

    ConcurrentKafkaListenerContainerFactory<Integer, String> factory = new ConcurrentKafkaListenerContainerFactory<>();
    factory.setConsumerFactory(consumerFactoryString());
    return factory;
  }

}
