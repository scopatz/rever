"""Activity for keeping a contributors listing."""
import os
import re
import sys
import json

from xonsh.tools import print_color

from rever import vcsutils
from rever.activity import Activity
from rever.tools import eval_version, replace_in_file
from rever.authors import update_metadata, write_mailmap


DEFAULT_TEMPLATE = """All of the people who have made at least one contribution to $PROJECT.
Authors are sorted {sorting_text}.

{authors}
"""
DEFAULT_FORMAT = "* {name}\n"
# flag: (sorter, sorting_text)
SORTINGS = {
    "num_commits": (lambda x: -x["num_commits"], "by number of commits"),
    "first_commit": (lambda x: x["first_commit"], "by date of first commit"),
    "alpha": (lambda x: x["name"], "alphabetically"),
    }


class Authors(Activity):
    """Manages keeping a contributors listing up-to-date.

    This activity may be configured with the following envionment variables:

    :$AUTHORS_FILENAME: str, path to input file. The default is 'AUTHORS'.
    :$AUTHORS_TEMPLATE: str or callable, This value goes at the top of the
        authors file. The default value is:

        .. code-block:: rst

            All of the people who have made at least one contribution to $PROJECT
            Authors are sorted by {sorting_text}.

            {authors}

        This is evaluated in the current environment and,

        * "{sorting_text}" is a special textual description of the sort method.
        * "{authors}" is a contcatenated string of all formatted authors.

        which the template is formatted with.
    :$AUTHORS_FORMAT: str, the string that formats each author in the author file.
        The default is ``"* {name}\n"``. The valid fields are all of those present
        in the author metadata (see below).
    :$AUTHORS_LATEST: str, file to write just the latest contribuors to, i.e.
        this is the listing of the contributors for just this release.
        This defaults to ``$REVER_DIR/LATEST-AUTHORS.json``. This is evaluated
        in the current environment.
    :$AUTHORS_METADATA: str, path to YAML file that stores author metadata.
        The default is '.authors.yml'. This is evaluated in the current environment.
        This file has the following format:

        .. code-block:: yaml

            # required fields
            - name: Princess Buttercup
              email: buttercup@florin.gov

              # optional fields
              github: bcup
              aliases:
                - Buttercup
                - beecup
              alternate_emails:
                - b.cup@gmail.com

              # autogenerated fields
              num_commits: 1000
              first_commit: '1987-09-25'
            - name: Westley
              email: westley@gamil.com
              github: westley
              aliases:
                - Dread Pirate Roberts
              alternate_emails:
                - dpr@pirates.biz
    :$AUTHORS_SORTBY: str, flag that specifies how authors should be sorted in
        the authors file. Valid options are:

        * ``"num_commits"``: Number of commits per author
        * ``"first_commit"``: Sort by first commit.
        * ``"alpha"``: Alphabetically.
    :$AUTHORS_MAILMAP: str, bool, or None, If this is a non-empty string,
        it will be interperted as a file path to a mailmap file that will be
        generated based on the metadata provided. The default value is  ``".mailmap"``.
        This is evaluated in the current environment.
    """

    def __init__(self, *, deps=frozenset()):
        super().__init__(name='authors', deps=deps, func=self._func,
                         desc="Manages keeping a contributors listing up-to-date.",
                         setup=self.setup_func)

    def _func(self, filename='AUTHORS',
              template=DEFAULT_TEMPLATE,
              format=DEFAULT_FORMAT,
              latest='$REVER_DIR/LATEST-AUTHORS.json',
              metadata='.authors.yml',
              sortby="num_commits",
              mailmap='.mailmap',
              ):
        latest = eval_version(latest)
        # Update authors file
        md = self._update_authors(filename, template, format, metadata, sortby)
        files = [filename, metadata]
        print_color('{YELLOW}wrote authors to {INTENSE_CYAN}' + filename + '{NO_COLOR}', file=sys.stderr)
        # write latest authors
        prev_version = vcsutils.latest_tag()
        commits_since_last = vcsutils.commits_per_email(since=prev_version)
        emails_since_last = set(commits_since_last.keys())
        latest_authors = [x["email"] for x in md
                          if len(set([x["email"]] + x.get("alternate_emails", [])) & emails_since_last) > 0]
        with open(latest, 'w') as f:
            json.dump(latest_authors, f)
        if not latest.startswith($REVER_DIR):
            # commit the latest file
            files.append(latest)
        print_color('{YELLOW}wrote authors since ' + prev_version + ' to {INTENSE_CYAN}' + latest + '{NO_COLOR}', file=sys.stderr)
        # write mailmap
        if mailmap and isinstance(mailmap, str):
            mailmap = eval_version(mailmap)
            write_mailmap(md, mailmap)
            files.append(mailmap)
            print_color('{YELLOW}wrote mailmap file to {INTENSE_CYAN}' + mailmap + '{NO_COLOR}', file=sys.stderr)
        # Commit changes
        vcsutils.track(files)
        vcsutils.commit('Updated authorship for ' + $VERSION)

    def setup_func(self):
        """Initializes the authors activity by (re-)starting an authors file
        from the current repo.
        """
        # get vars from env
        filename = ${...}.get('AUTHORS_FILENAME', 'AUTHORS')
        template = ${...}.get('AUTHORS_TEMPLATE', DEFAULT_TEMPLATE)
        format = ${...}.get('AUTHORS_FORMAT', DEFAULT_FORMAT)
        metadata = ${...}.get('AUTHORS_METADATA', '.authors.yml')
        sortby = ${...}.get('AUTHORS_SORTBY', 'num_commits')
        mailmap = ${...}.get('AUTHORS_MAILMAP', '.mailmap')
        # run saftey checks
        filename_exists = os.path.isfile(filename)
        metadata_exists = os.path.isfile(metadata)
        mailmap_exists = os.path.isfile(mailmap)
        msgs = []
        if filename_exists:
            msgs.append('Authors file {0!r} exists'.format(filename))
        if metadata_exists:
            msgs.append('Rever authors metadata file {0!r} exists'.format(metadata))
        if mailmap_exists:
            msgs.append('Mailmap file {0!r} exists'.format(mailmap))
        if len(msgs) > 0:
            print_color('{RED}' + ' AND '.join(msgs) + '{NO_COLOR}',
                        file=sys.stderr)
            if $REVER_FORCED:
                print_color('{RED}rever forced, overwriting files!{NO_COLOR}',
                            file=sys.stderr)
            else:
                print_color('{RED}Use the --force option to force the creation '
                            'of the changelog files.{NO_COLOR}',
                            file=sys.stderr)
                return False
        # actually create files
        md = self._update_authors(filename, template, format, metadata, sortby)
        if mailmap and isinstance(mailmap, str):
            mailmap = eval_version(mailmap)
            write_mailmap(md, mailmap)
        return True

    def _update_authors(self, filename, template, format, metadata, sortby):
        """helper fucntion for updating / writing authors file"""
        md = update_metadata(metadata)
        template = eval_version(template)
        sorting_key, sorting_text = SORTINGS[sortby]
        md = sorted(md, key=sorting_key)
        aformated = "".join([format.format(**x) for x in md])
        s = template.format(sorting_text=sorting_text, authors=aformated) + "\n"
        with open(filename, 'w') as f:
            f.write(s)
        return md
