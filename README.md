# Hermes-Client

`hermes-client` is a Ruby client library for the Hermes Agent API Server.

## Getting started

Install the gem using

```sh
gem install hermes-client
```

Or add it to your bundle:

```ruby
# In your Gemfile
gem "hermes-client"
```

Create and use a client object:

```ruby
require "hermes-client"

# Create a new client and point it at a Hermes Gateway server
hermes_client = HermesAgent::Client.new(
  base_url: "http://localhost:8642",
  api_key: "my-key-12345678"
)

# Send chat messages to the gateway
response = hermes_client.responses.create(input: "Tell me a joke.")
puts response.output_text

# Manage jobs
briefing_job = hermes_client.jobs.create(
  name: "daily-briefing",
  schedule: "every morning at 8am",
  prompt: "Collect the day's news and email me a summary."
)
puts "Daily-briefing will next run at #{briefing_job.next_run_at}"
```

A client is not thread-safe (it holds a persistent connection); create one
client per thread.

For more information, see the
[Hermes Gateway API documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server).

Full API documentation is available at https://dazuma.github.io/hermes-client
for released gems.

## Requirements and status

`hermes-client` requires Ruby 3.4 or later.

The gem can be considered alpha quality. Initial development is complete, but
the library has seen minimal real-world testing, and it may experience
significant changes, including breaking interface changes. It is available now
on an experimental basis, but not currently recommended for production use.

## Contributing

Development is done in GitHub at https://github.com/dazuma/hermes-client.

 *  To file issues: https://github.com/dazuma/hermes-client/issues.
 *  For questions and discussion, please do not file an issue. Instead, use the
    discussions feature: https://github.com/dazuma/hermes-client/discussions.
 *  Before opening any non-trivial pull request, please report a bug or feature
    request using an issue.

The library uses [toys](https://dazuma.github.io/toys) for testing and CI. To
run the test suite, `gem install toys` and then run `toys ci`. You can also run
unit tests, rubocop, and build tests independently.

As of late May, 2026, the documentation provided by Hermes is fairly thin, and
the developer had to cobble together an understanding of the API interfaces and
protocols from various sources, including the Hermes source and empirical
probing of a live gateway. Documents related to our findings are available in
the `devdocs` directory, and some Toys-based probing tools are also included in
this repository. (These are not included in the gem distribution.)

Much of the heavy lifting in the original implementation and documentation, as
well as the research behind it into the actual behavior of the gateway API, was
done in close collaboration with Claude Code (Opus 4.7).

## License

Copyright 2026 Daniel Azuma

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
