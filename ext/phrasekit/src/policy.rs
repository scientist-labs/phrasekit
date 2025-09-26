use crate::payload::Payload;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchPolicy {
    LeftmostLongest,
    LeftmostFirst,
    SalienceMax,
}

impl MatchPolicy {
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "leftmost_longest" => Some(Self::LeftmostLongest),
            "leftmost_first" => Some(Self::LeftmostFirst),
            "salience_max" => Some(Self::SalienceMax),
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    #[allow(dead_code)]
    pub pattern_id: usize,
    pub payload: Payload,
}

impl Match {
    pub fn new(start: usize, end: usize, pattern_id: usize, payload: Payload) -> Self {
        Self {
            start,
            end,
            pattern_id,
            payload,
        }
    }

    pub fn len(&self) -> usize {
        self.end - self.start
    }

    pub fn overlaps(&self, other: &Match) -> bool {
        !(self.end <= other.start || other.end <= self.start)
    }
}

pub fn resolve_overlaps(mut matches: Vec<Match>, policy: MatchPolicy) -> Vec<Match> {
    if matches.is_empty() {
        return matches;
    }

    matches.sort_by_key(|m| m.start);

    match policy {
        MatchPolicy::LeftmostLongest => resolve_leftmost_longest(matches),
        MatchPolicy::LeftmostFirst => resolve_leftmost_first(matches),
        MatchPolicy::SalienceMax => resolve_salience_max(matches),
    }
}

fn resolve_leftmost_longest(matches: Vec<Match>) -> Vec<Match> {
    let mut result = Vec::new();
    let mut current_end = 0;

    for group_start in 0..matches.len() {
        if matches[group_start].start < current_end {
            continue;
        }

        let group_end = matches[group_start..]
            .iter()
            .position(|m| m.start != matches[group_start].start)
            .map(|i| group_start + i)
            .unwrap_or(matches.len());

        let longest = matches[group_start..group_end]
            .iter()
            .max_by_key(|m| m.len())
            .unwrap()
            .clone();

        current_end = longest.end;
        result.push(longest);
    }

    result
}

fn resolve_leftmost_first(matches: Vec<Match>) -> Vec<Match> {
    let mut result = Vec::new();
    let mut current_end = 0;

    for m in matches {
        if m.start >= current_end {
            current_end = m.end;
            result.push(m);
        }
    }

    result
}

fn resolve_salience_max(matches: Vec<Match>) -> Vec<Match> {
    let mut result = Vec::new();
    let mut i = 0;

    while i < matches.len() {
        let mut j = i + 1;
        while j < matches.len() && matches[j].overlaps(&matches[i]) {
            j += 1;
        }

        let best = matches[i..j]
            .iter()
            .max_by(|a, b| {
                a.payload
                    .salience_score()
                    .partial_cmp(&b.payload.salience_score())
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .unwrap()
            .clone();

        result.push(best.clone());
        i = matches[i..]
            .iter()
            .position(|m| m.start >= best.end)
            .map(|idx| i + idx)
            .unwrap_or(matches.len());
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_match(start: usize, end: usize, salience: f32, count: u32) -> Match {
        Match::new(
            start,
            end,
            0,
            Payload::new(0, salience, count, (end - start) as u8),
        )
    }

    #[test]
    fn test_leftmost_longest() {
        let matches = vec![
            make_match(0, 2, 1.0, 100),
            make_match(0, 3, 1.0, 100),
            make_match(5, 7, 1.0, 100),
        ];

        let resolved = resolve_overlaps(matches, MatchPolicy::LeftmostLongest);
        assert_eq!(resolved.len(), 2);
        assert_eq!(resolved[0].len(), 3);
        assert_eq!(resolved[1].start, 5);
    }

    #[test]
    fn test_leftmost_first() {
        let matches = vec![
            make_match(0, 2, 1.0, 100),
            make_match(1, 3, 1.0, 100),
            make_match(3, 5, 1.0, 100),
        ];

        let resolved = resolve_overlaps(matches, MatchPolicy::LeftmostFirst);
        assert_eq!(resolved.len(), 2);
        assert_eq!(resolved[0].end, 2);
        assert_eq!(resolved[1].start, 3);
    }

    #[test]
    fn test_salience_max() {
        let matches = vec![
            make_match(0, 2, 1.0, 100),
            make_match(0, 3, 2.0, 200),
            make_match(5, 7, 1.0, 100),
        ];

        let resolved = resolve_overlaps(matches, MatchPolicy::SalienceMax);
        assert_eq!(resolved.len(), 2);
        assert_eq!(resolved[0].len(), 3);
    }
}