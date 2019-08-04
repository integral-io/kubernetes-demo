package io.integral.k8frastructure;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.Future;

@RestController
@Slf4j
public class LoggyController {

    private final LoggyService service;

    public LoggyController(final LoggyService service) {
        this.service = service;
    }

    @GetMapping("/log")
    public boolean startLogging() {
        final Future<Boolean> stuff = service.logStuff();
        return true;
    }

    @GetMapping("/log/stop")
    public boolean stopLogging() {
        return service.stopLogging();
    }
}
