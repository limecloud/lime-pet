use serde::Serialize;

const DEFAULT_COMPANION_ENDPOINT: &str = "ws://127.0.0.1:45554/companion/pet";
const DEFAULT_CLIENT_ID: &str = "lime";
const DEFAULT_PROTOCOL_VERSION: i32 = 1;

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
struct LaunchConfig {
    endpoint: Option<String>,
    client_id: String,
    protocol_version: i32,
}

#[tauri::command]
fn load_launch_config() -> LaunchConfig {
    parse_launch_config(std::env::args().skip(1))
}

fn parse_launch_config<I>(args: I) -> LaunchConfig
where
    I: IntoIterator<Item = String>,
{
    let mut endpoint = Some(DEFAULT_COMPANION_ENDPOINT.to_string());
    let mut client_id = DEFAULT_CLIENT_ID.to_string();
    let mut protocol_version = DEFAULT_PROTOCOL_VERSION;

    let mut iter = args.into_iter();
    while let Some(argument) = iter.next() {
        match argument.as_str() {
            "--connect" => {
                if let Some(value) = iter.next() {
                    endpoint = Some(value);
                }
            }
            "--client-id" => {
                if let Some(value) = iter.next() {
                    let trimmed = value.trim();
                    if !trimmed.is_empty() {
                        client_id = trimmed.to_string();
                    }
                }
            }
            "--protocol-version" => {
                if let Some(value) = iter.next() {
                    if let Ok(parsed) = value.parse::<i32>() {
                        protocol_version = parsed;
                    }
                }
            }
            "--connect-disabled" => {
                endpoint = None;
            }
            _ => {}
        }
    }

    LaunchConfig {
        endpoint,
        client_id,
        protocol_version,
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![load_launch_config])
        .run(tauri::generate_context!())
        .expect("error while running Lime Pet Windows");
}

#[cfg(test)]
mod tests {
    use super::{parse_launch_config, LaunchConfig};

    #[test]
    fn keeps_default_arguments() {
        let actual = parse_launch_config(Vec::<String>::new());
        let expected = LaunchConfig {
            endpoint: Some("ws://127.0.0.1:45554/companion/pet".to_string()),
            client_id: "lime".to_string(),
            protocol_version: 1,
        };
        assert_eq!(actual, expected);
    }

    #[test]
    fn parses_custom_arguments() {
        let actual = parse_launch_config(vec![
            "--connect".to_string(),
            "ws://127.0.0.1:45555/custom".to_string(),
            "--client-id".to_string(),
            "pet-shell".to_string(),
            "--protocol-version".to_string(),
            "3".to_string(),
        ]);

        let expected = LaunchConfig {
            endpoint: Some("ws://127.0.0.1:45555/custom".to_string()),
            client_id: "pet-shell".to_string(),
            protocol_version: 3,
        };
        assert_eq!(actual, expected);
    }

    #[test]
    fn supports_disabling_connection() {
        let actual = parse_launch_config(vec!["--connect-disabled".to_string()]);
        assert_eq!(
            actual,
            LaunchConfig {
                endpoint: None,
                client_id: "lime".to_string(),
                protocol_version: 1,
            }
        );
    }
}
