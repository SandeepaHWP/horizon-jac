impl Buckets.take(per_hour: float, key: str, most: int = MAX_BUCKETS) -> bool {
    rate = per_hour / 3600.0;
    burst = max(per_hour / 10.0, 1.0);
    now = time.monotonic();
    if len(self.tokens) >= most and key not in self.tokens {
        if self.swept is not None and now - self.swept < SWEEP_EVERY {
            return False;
        }
        self.swept = now;
        for k in list(self.tokens.keys()) {
            if self.tokens[k] + (now - self.at[k]) * rate >= burst {
                del self.tokens[k];
                del self.at[k];
            }
        }
        if len(self.tokens) >= most {
            return False;
        }
    }
    if key not in self.tokens {
        self.tokens[key] = burst;
        self.at[key] = now;
    }
    left = min(self.tokens[key] + (now - self.at[key]) * rate, burst);
    self.at[key] = now;
    if left < 1.0 {
        self.tokens[key] = left;
        return False;
    }
    self.tokens[key] = left - 1.0;
    return True;
}

impl Buckets.forget_idle {
    now = time.monotonic();
    for k in list(self.at.keys()) {
        if now - self.at[k] >= 3600.0 {
            del self.tokens[k];
            del self.at[k];
        }
    }
}
