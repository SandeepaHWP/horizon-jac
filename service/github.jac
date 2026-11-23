"""Opens an issue on GitHub: the only call this server makes to it. Errors never carry the token or
GitHub's answer body."""
import json;
import urllib.request;
import urllib.error;

"""Opens `issue` in `repo` (`owner/name`) through the API at `api`; its URL. RuntimeError says why
not."""
def open_issue(api: str, repo: str, token: str, issue: Issue) -> str;
