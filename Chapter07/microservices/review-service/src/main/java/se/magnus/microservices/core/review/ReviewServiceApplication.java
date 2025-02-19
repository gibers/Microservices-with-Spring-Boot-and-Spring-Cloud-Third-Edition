package se.magnus.microservices.core.review;

import org.crac.Context;
import org.crac.Core;
import org.crac.Resource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import reactor.core.scheduler.Scheduler;
import reactor.core.scheduler.Schedulers;

@SpringBootApplication
@ComponentScan("se.magnus")
public class ReviewServiceApplication implements Resource {

  private static final Logger LOG = LoggerFactory.getLogger(ReviewServiceApplication.class);

  private final Integer threadPoolSize;
  private final Integer taskQueueSize;

  @Autowired
  public ReviewServiceApplication(
    @Value("${app.threadPoolSize:10}") Integer threadPoolSize,
    @Value("${app.taskQueueSize:100}") Integer taskQueueSize
  ) {
    this.threadPoolSize = threadPoolSize;
    this.taskQueueSize = taskQueueSize;

    Core.getGlobalContext().register(this);
  }


  @Bean
  public Scheduler jdbcScheduler() {
    LOG.info("Creates a jdbcScheduler with thread pool size = {}", threadPoolSize);
    return Schedulers.newBoundedElastic(threadPoolSize, taskQueueSize, "jdbc-pool");
  }

  public static void main(String[] args) {
    ConfigurableApplicationContext ctx = SpringApplication.run(ReviewServiceApplication.class, args);

    String mysqlUrl = ctx.getEnvironment().getProperty("spring.datasource.url");
    String user = ctx.getEnvironment().getProperty("spring.datasource.username");
    LOG.info("Connected user '{}' to MySQL db: {}", user, mysqlUrl);
  }

  @Override
  public void beforeCheckpoint(Context<? extends Resource> context) {
    LOG.info("v1: CRaC's beforeCheckpoint callback method called...");
  }

  @Override
  public void afterRestore(Context<? extends Resource> context) {
    LOG.info("v1: CRaC's afterRestore callback method called...");
  }
}
