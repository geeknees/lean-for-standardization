// ABOUTME: Translate a common DNS/time/callback trace into Mozilla's public state-machine API.
// ABOUTME: Report observable connection outputs without implementing connection selection policy.
use happy_eyeballs::{
    ConnectionAttemptHttpVersions, ConnectionResult, DnsRecordType, DnsResult, HappyEyeballs,
    HttpVersion, HttpVersions, Id, Input, NetworkConfig, Output, ServiceInfo,
};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::io::{self, Read};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::time::{Duration, Instant};

fn keys(value: &Value, allowed: &[&str]) -> Result<(), String> {
    let object = value.as_object().ok_or("expected an object")?;
    for key in object.keys() {
        if !allowed.contains(&key.as_str()) {
            return Err(format!("unsupported field: {key}"));
        }
    }
    Ok(())
}

fn nat(value: &Value) -> Result<u64, String> {
    value
        .as_u64()
        .ok_or_else(|| "expected an unsigned integer".into())
}

fn address(value: &Value) -> Result<u8, String> {
    let number = nat(value)?;
    if !(1..=254).contains(&number) {
        return Err("address identifier must be in 1..=254".into());
    }
    Ok(number as u8)
}

fn ipv4(number: u8) -> Ipv4Addr {
    Ipv4Addr::new(192, 0, 2, number)
}
fn ipv6(number: u8) -> Ipv6Addr {
    Ipv6Addr::new(0x2001, 0xdb8, 0, 0, 0, 0, 0, number.into())
}

fn endpoint(value: &Value) -> Result<Value, String> {
    let family = value["family"].as_str().ok_or("missing address family")?;
    if !["ipv4", "ipv6"].contains(&family) {
        return Err("unsupported address family".into());
    }
    Ok(json!({"family":family, "address":address(&value["address"])?}))
}

fn from_ip(ip: IpAddr) -> Result<Value, String> {
    match ip {
        IpAddr::V4(ip) if ip.octets()[..3] == [192, 0, 2] => {
            endpoint(&json!({"family":"ipv4", "address":ip.octets()[3]}))
        }
        IpAddr::V6(ip) if ip.segments()[..7] == [0x2001, 0xdb8, 0, 0, 0, 0, 0] => {
            endpoint(&json!({"family":"ipv6", "address":ip.segments()[7]}))
        }
        _ => Err("implementation returned an address outside the fixture domain".into()),
    }
}

#[derive(PartialEq)]
enum AttemptState {
    Active,
    Failed,
    Cancelled,
    Succeeded,
}

struct Attempt {
    id: Id,
    endpoint: Value,
    state: AttemptState,
}

struct Driver {
    he: HappyEyeballs,
    epoch: Instant,
    now: u64,
    dns: HashMap<DnsRecordType, Id>,
    attempts: Vec<Attempt>,
    starts: Vec<Value>,
    cancelled: Vec<Value>,
    winner: Option<Value>,
    pending_success: Option<Value>,
    outputs: Vec<Value>,
}

impl Driver {
    fn instant(&self) -> Result<Instant, String> {
        self.epoch
            .checked_add(Duration::from_millis(self.now))
            .ok_or_else(|| "time overflow".into())
    }

    fn observe(&self) -> Value {
        let mut cancelled = self.cancelled.clone();
        cancelled.sort_by_key(|e| {
            (
                e["family"].as_str().unwrap().to_owned(),
                e["address"].as_u64().unwrap(),
            )
        });
        json!({"starts":self.starts, "winner":self.winner, "cancelled":cancelled})
    }

    fn pump(&mut self, event_index: i64) -> Result<(), String> {
        // The public API requires draining through Timer/None. Terminal outputs repeat,
        // so stop at Succeeded/Failed too; never hide additional AttemptConnection outputs.
        for _ in 0..1024 {
            let Some(output) = self.he.process_output(self.instant()?) else {
                return Ok(());
            };
            let mut stop = false;
            let observation = match output {
                Output::SendDnsQuery {
                    id,
                    hostname,
                    record_type,
                    allow_stale,
                } => {
                    let host: String = hostname.into();
                    if host != "example.com" || !allow_stale {
                        return Err("unexpected target or DNS refresh".into());
                    }
                    if self.dns.insert(record_type, id).is_some() {
                        return Err("duplicate DNS query".into());
                    }
                    json!({"kind":"dnsQuery", "record":format!("{record_type:?}"), "id":format!("{id:?}")})
                }
                Output::Timer { duration } => {
                    stop = true;
                    json!({"kind":"timer", "ms":duration.as_millis()})
                }
                Output::AttemptConnection {
                    id,
                    endpoint,
                    is_ech_retry,
                } => {
                    if endpoint.http_version != ConnectionAttemptHttpVersions::H2
                        || endpoint.ech_config.is_some()
                        || is_ech_retry
                    {
                        return Err("unexpected protocol or ECH retry".into());
                    }
                    let socket = endpoint.address().ok_or("unexpected by-name endpoint")?;
                    if socket.port() != 443 {
                        return Err("unexpected port".into());
                    }
                    let ep = from_ip(socket.ip())?;
                    self.starts.push(json!({"endpoint":ep, "at":self.now}));
                    self.attempts.push(Attempt {
                        id,
                        endpoint: ep.clone(),
                        state: AttemptState::Active,
                    });
                    json!({"kind":"attempt", "endpoint":ep})
                }
                Output::CancelConnection { id } => {
                    let attempt = self
                        .attempts
                        .iter_mut()
                        .find(|a| a.id == id)
                        .ok_or("unknown cancellation")?;
                    if attempt.state != AttemptState::Active {
                        return Err("cancellation for inactive attempt".into());
                    }
                    attempt.state = AttemptState::Cancelled;
                    self.cancelled.push(attempt.endpoint.clone());
                    json!({"kind":"cancel", "endpoint":attempt.endpoint})
                }
                Output::Succeeded => {
                    if self.winner.is_none() {
                        let ep = self
                            .pending_success
                            .take()
                            .ok_or("success output without a success callback")?;
                        let attempt = self
                            .attempts
                            .iter_mut()
                            .find(|a| a.endpoint == ep && a.state == AttemptState::Active)
                            .ok_or("successful attempt is not active")?;
                        attempt.state = AttemptState::Succeeded;
                        self.winner = Some(ep);
                    }
                    stop = true;
                    json!({"kind":"succeeded", "winner":self.winner})
                }
                Output::Failed(reason) => {
                    stop = true;
                    json!({"kind":"failed", "reason":format!("{reason:?}")})
                }
            };
            self.outputs
                .push(json!({"event":event_index, "at":self.now, "output":observation}));
            if stop {
                return Ok(());
            }
        }
        Err("output drain exceeded 1024 outputs".into())
    }

    fn dns_result(&mut self, record: DnsRecordType, result: DnsResult) -> Result<(), String> {
        let id = self
            .dns
            .remove(&record)
            .ok_or("DNS response has no pending query (duplicate or unsupported update)")?;
        self.he.process_input(
            Input::DnsResult {
                id,
                result,
                stale: false,
            },
            self.instant()?,
        );
        Ok(())
    }

    fn feed(&mut self, event: &Value) -> Result<(), String> {
        match event["kind"].as_str().ok_or("missing event kind")? {
            kind @ ("dnsA" | "dnsAAAA") => {
                keys(event, &["kind", "addresses"])?;
                let addresses = event["addresses"].as_array().ok_or("missing address array")?
                    .iter().map(address).collect::<Result<Vec<_>, _>>()?;
                if kind == "dnsA" {
                    self.dns_result(DnsRecordType::A, DnsResult::A(Ok(addresses.into_iter().map(ipv4).collect())))?;
                } else {
                    self.dns_result(DnsRecordType::Aaaa, DnsResult::Aaaa(Ok(addresses.into_iter().map(ipv6).collect())))?;
                }
            }
            "https" => {
                keys(event, &["kind", "answer", "hints"])?;
                let hints = event.get("hints").map(|h| h.as_array().ok_or("hints must be an array")).transpose()?
                    .cloned().unwrap_or_default();
                let infos = match event["answer"].as_str() {
                    Some("noData") if hints.is_empty() => vec![],
                    Some("service") => {
                        let mut info = ServiceInfo { priority:1, target_name:"example.com".into(),
                            alpn_http_versions:[HttpVersion::H2].into_iter().collect(), ech_config:None,
                            ipv4_hints:vec![], ipv6_hints:vec![], port:None };
                        for hint in hints {
                            keys(&hint, &["family", "address"])?;
                            let ep = endpoint(&hint)?;
                            let number = address(&ep["address"])?;
                            if ep["family"] == "ipv4" { info.ipv4_hints.push(ipv4(number)); }
                            else { info.ipv6_hints.push(ipv6(number)); }
                        }
                        vec![info]
                    }
                    _ => return Err("only service and empty noData HTTPS answers are in the comparison domain".into())
                };
                self.dns_result(DnsRecordType::Https, DnsResult::Https(Ok(infos)))?;
            }
            "advance" => {
                keys(event, &["kind", "ms"])?;
                self.now = self.now.checked_add(nat(&event["ms"])?).ok_or("time overflow")?;
            }
            kind @ ("success" | "failure") => {
                keys(event, &["kind", "family", "address"])?;
                let ep = endpoint(event)?;
                let attempt = self.attempts.iter_mut().find(|a| a.endpoint == ep).ok_or("callback has no emitted attempt")?;
                if attempt.state != AttemptState::Active && attempt.state != AttemptState::Cancelled {
                    return Err("duplicate callback for completed attempt".into());
                }
                if attempt.state == AttemptState::Active {
                    if kind == "success" { self.pending_success = Some(ep); }
                    else { attempt.state = AttemptState::Failed; }
                }
                let id = attempt.id;
                let result = if kind == "success" { ConnectionResult::Success }
                    else { ConnectionResult::Failure("fixture failure".into()) };
                self.he.process_input(Input::ConnectionResult { id, result }, self.instant()?);
            }
            _ => return Err("unsupported event (TLS, explicit starts, aliases, refresh, and external cancellation are outside this adapter)".into())
        }
        Ok(())
    }
}

fn evaluate(input: &Value) -> Result<Value, String> {
    keys(input, &["config", "events"])?;
    let config = input.get("config").cloned().unwrap_or_else(|| json!({}));
    keys(&config, &["resolutionDelay", "attemptDelay"])?;
    let resolution = config
        .get("resolutionDelay")
        .map(nat)
        .transpose()?
        .unwrap_or(50);
    let attempt = config
        .get("attemptDelay")
        .map(nat)
        .transpose()?
        .unwrap_or(250);
    let he = HappyEyeballs::new_with_network_config(
        "example.com",
        443,
        NetworkConfig {
            http_versions: HttpVersions {
                h1: false,
                h2: true,
                h3: false,
            },
            ech: false,
            resolution_delay: Duration::from_millis(resolution),
            connection_attempt_delay: Duration::from_millis(attempt),
            ..NetworkConfig::default()
        },
    )
    .map_err(|e| e.to_string())?;
    let mut driver = Driver {
        he,
        epoch: Instant::now(),
        now: 0,
        dns: HashMap::new(),
        attempts: vec![],
        starts: vec![],
        cancelled: vec![],
        winner: None,
        pending_success: None,
        outputs: vec![],
    };
    let events = input["events"].as_array().ok_or("missing event array")?;
    if events.len() > 10_000 {
        return Err("trace exceeds 10000 events".into());
    }
    driver.pump(-1)?;
    let mut timeline = vec![];
    for (index, event) in events.iter().enumerate() {
        driver
            .feed(event)
            .map_err(|e| format!("event {index}: {e}"))?;
        driver
            .pump(index as i64)
            .map_err(|e| format!("event {index}: {e}"))?;
        timeline.push(driver.observe());
    }
    Ok(json!({"timeline":timeline, "final":driver.observe(), "outputs":driver.outputs}))
}

fn main() {
    let mut input = String::new();
    let result = io::stdin()
        .read_to_string(&mut input)
        .map_err(|e| e.to_string())
        .and_then(|_| serde_json::from_str(&input).map_err(|e| e.to_string()))
        .and_then(|value| evaluate(&value));
    match result {
        Ok(output) => println!("{output}"),
        Err(error) => {
            eprintln!("{error}");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dns_completion_starts_the_pinned_implementation() {
        let result = evaluate(&json!({"events": [
            {"kind": "dnsAAAA", "addresses": [6]},
            {"kind": "https", "answer": "noData"}
        ]}))
        .unwrap();
        assert_eq!(
            result["timeline"][1]["starts"],
            json!([
                {"endpoint": {"family":"ipv6", "address":6}, "at":0}
            ])
        );
    }

    #[test]
    fn success_cancels_the_loser_and_late_callback_does_not_change_winner() {
        let result = evaluate(&json!({"events": [
            {"kind":"dnsAAAA", "addresses":[6]},
            {"kind":"dnsA", "addresses":[4]},
            {"kind":"https", "answer":"noData"},
            {"kind":"advance", "ms":250},
            {"kind":"success", "family":"ipv4", "address":4},
            {"kind":"success", "family":"ipv6", "address":6}
        ]}))
        .unwrap();
        assert_eq!(
            result["timeline"][5]["winner"],
            json!({"family":"ipv4", "address":4})
        );
        assert_eq!(
            result["timeline"][5]["cancelled"],
            json!([{"family":"ipv6", "address":6}])
        );
        assert_eq!(result["timeline"][4], result["timeline"][5]);
    }

    #[test]
    fn unsupported_inputs_are_errors_instead_of_simulated_protocol_rejections() {
        for input in [
            json!({"events":[{"kind":"https", "answer":"alias"}]}),
            json!({"events":[{"kind":"dnsA", "addresses":[256]}]}),
            json!({"events":[{"kind":"success", "family":"ipv6", "address":6}]}),
            json!({"config":{"dnsProtected":true}, "events":[]}),
            json!({"events":[{"kind":"advance", "ms":-1}]}),
        ] {
            assert!(
                evaluate(&input).is_err(),
                "accepted unsupported input: {input}"
            );
        }
    }
}
