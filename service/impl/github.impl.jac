impl open_issue(api: str, repo: str, token: str, issue: Issue) -> str {
    body = json.dumps({"title": issue.title, "body": issue.body, "labels": issue.labels}).encode();
    req = urllib.request.Request(
        f"{api}/repos/{repo}/issues",
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "horizon-telemetry-server",
            "Content-Type": "application/json"
        }
    );
    try {
        with urllib.request.urlopen(req, timeout=20.0) as resp {
            answer: any = json.loads(resp.read().decode("utf-8"));
            if isinstance(answer, dict) and isinstance(answer.get("html_url"), str) {
                return answer["html_url"];
            }
            raise RuntimeError("GitHub's answer had no issue URL");
        }
    } except urllib.error.HTTPError as e {
        raise RuntimeError(f"GitHub answered {e.code}");
    } except urllib.error.URLError as e {
        raise RuntimeError(f"could not reach GitHub: {e.reason}");
    } except (OSError, ValueError) as e {
        raise RuntimeError(f"could not reach GitHub: {e}");
    }
}
