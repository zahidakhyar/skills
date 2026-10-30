#!/usr/bin/env bash
# Review-thread plumbing. GitHub exposes resolve and thread replies only through
# GraphQL, so this wraps the calls that are easy to get subtly wrong.
#
#   threads.sh list <PR>               - unresolved threads as JSON (path, line, isOutdated, comments)
#   threads.sh all <PR>                - every thread, resolved included
#   threads.sh resolve <ID>            - resolve one thread by its node id
#   threads.sh reply <ID> "<body>"     - reply inside one thread (published immediately)
#
# list/all walk every page: GraphQL caps a connection at 100 nodes and a PR that
# has been through a few review rounds gets there.
set -euo pipefail

cmd="${1:?usage: threads.sh list|all <PR> | resolve <thread-id> | reply <thread-id> <body>}"

case "$cmd" in
  resolve)
    gh api graphql -f id="${2:?thread id required}" -f query='
      mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }'
    exit 0 ;;
  reply)
    gh api graphql -f id="${2:?thread id required}" -f body="${3:?body required}" -f query='
      mutation($id:ID!,$body:String!){
        addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$id, body:$body}){
          comment{ url } } }'
    exit 0 ;;
esac

PR="${2:?PR number required}"
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# --paginate follows pageInfo.endCursor and prints one JSON document per page;
# jq -s merges them back into a single array.
out=$(gh api graphql --paginate -F pr="$PR" \
  -f owner="${repo%%/*}" -f name="${repo##*/}" -f query='
  query($owner:String!,$name:String!,$pr:Int!,$endCursor:String){
    repository(owner:$owner,name:$name){ pullRequest(number:$pr){
      reviewThreads(first:100, after:$endCursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id isResolved isOutdated path line originalLine
          comments(first:100){ nodes{ databaseId author{login} body createdAt } } } } } } }')

filter='[.[].data.repository.pullRequest.reviewThreads.nodes[]]'
[ "$cmd" = "list" ] && filter="$filter | map(select(.isResolved | not))"
echo "$out" | jq -sc "$filter"
