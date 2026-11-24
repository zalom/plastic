# frozen_string_literal: true

module Plastic
  class CLI
    # The families of the work graph and the hooks: the commands that start with node, edge, graph or hook.
    # The table in table.rb adds them to the other families, in this order.
    WORK_FAMILIES = {
      "node" => {
        "node add" => ["Commands::Node::Add", "Add a node to an intent's work graph, of kind work, orchestrator or retrieval"],
        "node remove" => ["Commands::Node::Remove", "Remove a node; its edges stay as rows"],
        "node claim" => ["Commands::Node::Claim", "Claim an open node, or take a lapsed claim, and print its brief"],
        "node renew" => ["Commands::Node::Renew", "Renew this session's claim on a node so it does not lapse"],
        "node release" => ["Commands::Node::Release", "Release a claimed or failed node back to open"],
        "node done" => ["Commands::Node::Done", "Mark a claimed node done, with its findings as TEXT"],
        "node fail" => ["Commands::Node::Fail", "Mark a claimed node failed, with the reason as TEXT"],
        "node ask" => ["Commands::Node::Ask", "Move a claimed node to needs_info with a question for the owner"],
        "node impede" => ["Commands::Node::Impede", "Move a claimed node to impeded with the impediment"],
        "node resolve" => ["Commands::Node::Resolve", "Reopen a needs_info or impeded node with its resolution"]
      },
      "edge" => {
        "edge add" => ["Commands::Edge::Add", "Add a needs edge between two nodes"],
        "edge remove" => ["Commands::Edge::Remove", "Remove an edge"]
      },
      "graph" => {
        "graph check" => ["Commands::Graph::Check", "Find a done node with no findings, an isolated node, a retry cap, no done criterion, a need on a removed node, a loop, output that is not JSON or a schema file with no live node"],
        "graph lapsed" => ["Commands::Graph::Lapsed", "List the agent deliveries whose claims lapsed and the command that restarts each"],
        "graph ready" => ["Commands::Graph::Ready", "List the nodes ready to claim"],
        "graph resume" => ["Commands::Graph::Resume", "Say where each named store's work stopped and what runs next"],
        "graph show" => ["Commands::Graph::Show", "Print every node, with the node it was found in, and every need of an intent"]
      },
      "chat" => {
        "chat list" => ["Commands::Chat::List", "List the recorded chat messages of every store in time order, from a day on with --since"]
      },
      "hook" => {
        "hook start" => ["Hooks::Start", "SessionStart: name the harness, open the session row, print the state the rows carry"],
        "hook prompt" => ["Hooks::Prompt", "UserPromptSubmit: record the prompt in the machine's chat history"],
        "hook stop" => ["Hooks::Stop", "Stop: stamp the turn, renew claims, run the stop gate"],
        "hook end" => ["Hooks::End", "SessionEnd: set the session's end time and reason"]
      }
    }.freeze
  end
end
