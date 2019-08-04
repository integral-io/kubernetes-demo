package io.integral.k8frastructure;

import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.AsyncResult;
import org.springframework.stereotype.Component;

import java.util.concurrent.Future;

@Component
@Slf4j
public class LoggyService {

    private boolean loggy = false;

    @Async
    public Future<Boolean> logStuff() {
        log.warn("Execute method asynchronously - "
                + Thread.currentThread().getName());
        try {
            doTheLogging();
            return new AsyncResult<Boolean>(Boolean.TRUE);
        } catch (Exception ignored) {}

        return null;
    }

    public boolean stopLogging() {
        loggy = false;
        return loggy;
    }

    private void doTheLogging() {
        loggy = true;
        log.info("Logging, Logging, Logging ....");
        while (loggy) {
            try {
                Thread.sleep(1000);
            } catch (InterruptedException e) {
                break;
            }
            log.info("Keep on, Keep on Logging ....");
        }
        log.info("HALT!");
    }
}
