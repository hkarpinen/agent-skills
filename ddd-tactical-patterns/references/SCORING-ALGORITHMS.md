# Scoring and Ranking Algorithms

> **Scope**: Domain-level scoring patterns implemented as Engines (domain services).
> These are business rules — they belong in the Domain layer. The Engine
> receives data; it does not perform I/O.

---

## When to Use

Any system that ranks user-generated content: forums, Q&A sites, social feeds, product reviews.
The scoring algorithm is a prime example of a **volatility axis** — it changes independently
of the content model, often based on A/B testing or product experimentation.

---

## Hot Ranking (Time-Decay + Votes)

Reddit-style "hot" ranking that balances recency with popularity. Newer content with moderate
votes ranks above older content with many votes.

### Algorithm

```
score = log10(max(|votes|, 1)) + sign(votes) × (created_epoch / 45000)
```

Where:
- `votes` = upvotes − downvotes (net score)
- `created_epoch` = seconds since a fixed epoch (e.g., Unix epoch or app launch date)
- `45000` ≈ 12.5 hours — controls how fast time decays relative to votes
- `log10` compresses vote differences (10 votes ≈ 100 votes in influence)

### Pseudocode Engine

```
class HotRankingEngine
    CalculateHotScore(upvotes: int, downvotes: int, createdAt: datetime) -> decimal
        netVotes = upvotes - downvotes
        magnitude = log10(max(abs(netVotes), 1))
        sign = if netVotes > 0 then 1
               else if netVotes < 0 then -1
               else 0
        epochSeconds = (createdAt - referenceEpoch).TotalSeconds
        return round(magnitude + sign * epochSeconds / 45000, 7)
```

Rules:
- Recalculate the hot score on every vote change. Store the score as a denormalized column
  on the content table for efficient `ORDER BY`.
- The divisor (45000) is a tuning parameter. Lower values make time more important (content
  cycles faster); higher values make votes more important.
- Use `log10` to prevent viral content from dominating indefinitely — the difference between
  10 and 100 votes is the same as between 100 and 1000.

---

## Wilson Score (Confidence-Based Ranking)

For "top" or "best" ranking — orders content by confidence that the true approval
rate is high, given the observed votes. Handles low-sample-size content fairly.

### Algorithm

Lower bound of the Wilson score confidence interval for a Bernoulli parameter:

$$
\text{score} = \frac{\hat{p} + \frac{z^2}{2n} - z\sqrt{\frac{\hat{p}(1-\hat{p})}{n} + \frac{z^2}{4n^2}}}{1 + \frac{z^2}{n}}
$$

Where:
- $\hat{p}$ = upvotes / total votes (observed approval rate)
- $n$ = total votes (upvotes + downvotes)
- $z$ = 1.96 for 95% confidence

### Pseudocode Engine

```
class WilsonScoreEngine
    CalculateWilsonScore(upvotes: int, downvotes: int) -> decimal
        n = upvotes + downvotes
        if n == 0
            return 0

        p = upvotes / n
        z = 1.96   // 95% confidence

        numerator = p + z*z/(2*n) - z * sqrt((p*(1-p) + z*z/(4*n)) / n)
        denominator = 1 + z*z/n

        return numerator / denominator
```

Rules:
- Wilson score is best for "top" or "best" sorting — it penalizes content with few votes
  rather than ranking a 1-upvote, 0-downvote post above a 99-upvote, 1-downvote post.
- Use hot ranking for "hot" feeds (recency matters). Use Wilson score for "best" feeds
  (quality matters, time-independent).

---

## Simple Sorts (No Algorithm Needed)

| Sort | Implementation |
|---|---|
| **New** | `ORDER BY created_at DESC` — no scoring needed |
| **Top (period)** | Filter by time window + `ORDER BY (upvotes - downvotes) DESC` |
| **Controversial** | `ORDER BY (upvotes + downvotes) DESC WHERE abs(upvotes - downvotes) < threshold` |

---

## Storage and Indexing

Store the computed score as a denormalized column on the content table:

```sql
ALTER TABLE forum.threads ADD COLUMN hot_score numeric(15,7) NOT NULL DEFAULT 0;
ALTER TABLE forum.threads ADD COLUMN wilson_score numeric(10,7) NOT NULL DEFAULT 0;

CREATE INDEX ix_threads_hot ON forum.threads (hot_score DESC, id)
    WHERE deleted_at IS NULL;
CREATE INDEX ix_threads_wilson ON forum.threads (wilson_score DESC, id)
    WHERE deleted_at IS NULL;
```

Rules:
- Recalculate and `UPDATE` the score column on every vote change. The Engine computes the
  value; the Manager calls `UPDATE`.
- Use composite indexes `(score DESC, id)` for cursor-based pagination on ranked feeds.
- Never compute scores at query time — it prevents index usage and degrades under load.

---

## Engine Placement in IDesign

The scoring Engine lives in the **Domain layer**. It is stateless and performs no I/O.

```
VoteWorkflowManager (Application)
  → loads Vote aggregate, Thread/Post aggregate
  → calls VoteTallyEngine.CalculateHotScore(upvotes, downvotes, createdAt)
  → updates thread.HotScore
  → saves via repository
```

The Manager owns the orchestration. The Engine owns the math.
