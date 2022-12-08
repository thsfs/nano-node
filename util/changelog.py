import argparse
import copy
import sys
import re
from typing import Tuple

"""
Changelog generation script, requires PAT with public_repo access, 
see https://github.com/settings/tokens

usage: changelog [-h] [-e END] [-m {final,beta}] -p PAT [-r REPO] [-s START] [-t TAG]

Generate Changelogs between tags or commits

optional arguments:
  -h, --help            Show this help message and exit
  -e END, --end END     Ending reference for Changelog(newest)
  -m {final,beta}, --mode {final,beta}
                        Mode to run changelog for [final, beta]
  -p PAT, --pat PAT     Personal Access Token
  -r REPO, --repo REPO  <org/repo> to generate logs for
  -s START, --start START
                        Starting reference for Changelog(oldest)
  -t TAG, --tag TAG     Tag to use for changelog generation
  -v, --verbose         Verbose mode
"""


final = re.compile(r"^(V(\d)+.(\d)+)$")
beta = re.compile(r"^(V(\d)+.(\d)+((RC(\d)+)|(DB(\d)+))?)$")

try:
    from github import Github, UnknownObjectException
    from mdutils import MdUtils
except BaseException:
    sys.exit("Error: run 'pip install PyGithub mdutils'")

SECTIONS = {
    "Major Changes": [
        "major",
    ],
    "Protocol Changes": [
        "protocol change",
    ],
    "Node Configuration Updates": [
        "toml",
        "configuration default change",
    ],
    "RPC Updates": [
        "rpc",
    ],
    "IPC Updates": [
        "ipc",
    ],
    "Websocket Updates": [
        "websockets",
    ],
    "CLI Updates": [
        "cli",
    ],
    "Deprecation/Removal": [
        "deprecation",
        "removal",
    ],
    "Developer Wallet": [
        "qt wallet",
    ],
    "Ledger & Database": [
        "database",
        "database structure",
    ],
    "Developer/Debug Options": [
        "debug",
        "logging",
    ],
    "Fixed Bugs": [
        "bug",
    ],
    "Implemented Enhancements": [
        "enhancement",
        "functionality quality improvements",
        "performance",
        "quality improvements",
    ],
    "Build, Test, Automation, Cleanup & Chores": [
        "build-error",
        "documentation",
        "non-functional change",
        "routine",
        "sanitizers",
        "static-analysis",
        "tool",
        "unit test",
        "universe",
    ],
    "Other": []
}


class CliArgs:
    def __init__(self) -> dict:

        changelog_choices = ["final", "beta"]

        parse = argparse.ArgumentParser(
            prog="changelog",
            description="Generate Changelogs between tags or commits"
        )
        parse.add_argument(
            '-e', '--end',
            help="Ending reference for Changelog(newest)",
            type=str, action="store",
        )
        parse.add_argument(
            "-m", "--mode",
            help="Mode to run changelog for [final, beta]",
            type=str, action="store",
            default="beta",
            choices=changelog_choices
        )
        parse.add_argument(
            '-p', '--pat',
            help="Personal Access Token",
            type=str, action="store",
            required=True,
        )
        parse.add_argument(
            '-r', '--repo',
            help="<org/repo> to generate logs for",
            type=str, action="store",
            default='nanocurrency/nano-node',
        )
        parse.add_argument(
            '-s', '--start',
            help="Starting reference for Changelog(oldest)",
            type=str, action="store",
        )
        parse.add_argument(
            '-t', '--tag',
            help="Tag to use for changelog generation",
            type=str, action="store"
        )
        parse.add_argument(
            '-v', '--verbose',
            help="Verbose mode",
            action="store_true"
        )
        options = parse.parse_args()
        self.end = options.end
        self.mode = options.mode
        self.pat = options.pat
        self.repo = options.repo.rstrip("/")
        self.start = options.start
        self.tag = options.tag
        self.verbose = options.verbose


class GenerateTree:
    def __init__(self, args):
        github = Github(args.pat)
        self.name = args.repo
        self.repo = github.get_repo(self.name)
        self.args = args
        if args.tag:
            self.tag = args.tag
            self.end = self.repo.get_commit(args.tag).sha
            if args.end:
                print("error: set either --end or --tag")
                exit(1)
        if args.end:
            self.end = self.repo.get_commit(args.end).sha
            if not args.start:
                print("error: --end argument requires --start")
                exit(1)
        if not args.end and not args.tag:
            print("error: need either --end or --tag")
            exit(1)

        if args.start:
            self.start = self.repo.get_commit(args.start).sha
        else:
            assert args.tag
            self.start = self.get_common_by_tag(args.mode)

        self.commits = {}
        self.other_commits = []
        commits = self.repo.get_commits(sha=self.end)

        # Check if the common ancestor exists in the commit list.
        found_common_ancestor = False
        for commit in commits:
            if commit.sha == self.start:
                found_common_ancestor = True
                break
        if not found_common_ancestor:
            print("error: the common ancestor was not found")
            exit(1)

        # Retrieve the complementary information for each commit.
        for commit in commits:
            if commit.sha == self.start:
                break
            m = commit.commit.message.partition('\n')[0]
            try:
                pr_number = int(m[m.rfind('#')+1:m.rfind(')')])
                pull = self.repo.get_pull(pr_number)
            except (ValueError, UnknownObjectException):
                p = commit.get_pulls()
                if p.totalCount > 0:
                    pr_number = p[0].number
                    pull = self.repo.get_pull(pr_number)
                else:
                    if args.verbose:
                        print(f"commit has no associated PR {commit.sha}: \"{m}\"")
                    self.other_commits.append((commit.sha, m))
                    continue

            labels = []
            for label in pull.labels:
                labels.append(label.name)
            self.commits[pull.number] = {
                "Title": pull.title,
                "Url": pull.html_url,
                "labels": labels
            }

    def get_common_by_tag(self, start) -> str:
        tree = self.repo.compare(self.end, selected_tag.commit.sha)
        selected_commit = tree.merge_base_commit.sha
        if self.args.verbose:
            print(f"got the merge base commit: {selected_commit}")
        return selected_commit

    def get_common_by_tag(self, mode) -> str:
        tags = []
        found_end_tag = False
        for tag in self.repo.get_tags():
            if not found_end_tag and tag.name == self.tag:
                found_end_tag = True
            if found_end_tag:
                if mode == "final":
                    matched_tag = final.match(tag.name)
                else:
                    matched_tag = beta.match(tag.name)
                if matched_tag:
                    tags.append(tag)

        if len(tags) < 2:
            return None
        selected_tag = tags[1]

        if self.args.verbose:
            print(f"selected start tag {selected_tag.name}: {selected_tag.commit.sha}")

        start_version = re.search(r"(\d)+.", selected_tag.name)
        tag_version = re.search(r"(\d)+.", self.tag)
        if start_version and tag_version and start_version.group(0) == tag_version.group(0):
            if self.args.verbose:
                print(f"selected start commit {selected_tag.commit.sha} ({selected_tag.name}) "
                      f"has the same major version of the end tag ({self.tag})")
            return selected_tag.commit.sha

        tree = self.repo.compare(self.end, selected_tag.commit.sha)
        selected_commit = tree.merge_base_commit.sha
        if self.args.verbose:
            print(f"got the merge base commit: {selected_commit}")
        return selected_commit


class GenerateMarkdown:
    def __init__(self, repo: GenerateTree):
        self.mdFile = MdUtils(
            file_name='CHANGELOG', title='CHANGELOG'
        )
        if repo.tag:
            self.mdFile.new_line(
                "## Release " +
                f"[{repo.tag}](https://github.com/{repo.name}/tree/{repo.tag})", wrap_width=0)
        else:
            self.mdFile.new_line(
                f"[{repo.end}](https://github.com/{repo.name}/tree/{repo.end})", wrap_width=0)
        self.mdFile.new_line(f"[Full Changelog](https://github.com/{repo.name}"
                             f"/compare/{repo.start}...{repo.end})", wrap_width=0)
        sort = self.pull_to_section(repo.commits)
        for section, prs in sort.items():
            self.write_header_pr(section)
            for pr in prs:
                self.write_pr(pr, repo.commits[pr[0]])
        if repo.other_commits:
            self.write_header_no_pr()
            for sha, message in repo.other_commits:
                self.write_no_pr(repo, sha, message)
        self.mdFile.create_md_file()

    def write_header_pr(self, section):
        self.mdFile.new_line("---")
        self.mdFile.new_header(level=3, title=section,
                               add_table_of_contents='n')
        self.mdFile.new_line(
            "|Pull Request|Title")
        self.mdFile.new_line("|:-:|:--")

    def write_header_no_pr(self):
        self.mdFile.new_line()
        self.mdFile.new_line(
            "|Commit|Title")
        self.mdFile.new_line("|:-:|:--")

    def write_pr(self, pr, info):
        imp = ""
        if pr[1]:
            imp = "**BREAKING** "
        self.mdFile.new_line(
            f"|[#{pr[0]}]({info['Url']})|{imp}{info['Title']}", wrap_width=0)

    def write_no_pr(self, repo, sha, message):
        url = f"https://github.com/{repo.name}/commit/{sha}"
        self.mdFile.new_line(
            f"|[{sha[:8]}]({url})|{message}", wrap_width=0)

    @staticmethod
    def handle_labels(labels) -> Tuple[str, bool]:
        for section, values in SECTIONS.items():
            for label in labels:
                if label in values:
                    if any(
                            string in labels for string in [
                                'breaking',
                            ]):
                        return section, True
                    else:
                        return section, False
        return 'Other', False

    def pull_to_section(self, commits) -> dict:
        sect = copy.deepcopy(SECTIONS)
        result = {}
        for a in sect:
            sect[a] = []
        for pull, info in commits.items():
            section, important = self.handle_labels(info['labels'])
            if important:
                sect[section].insert(0, [pull, important])
            else:
                sect[section].append([pull, important])
        for a in sect:
            if len(sect[a]) > 0:
                result[a] = sect[a]
        return result


arg = CliArgs()
trees = GenerateTree(arg)
GenerateMarkdown(trees)
