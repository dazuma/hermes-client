# frozen_string_literal: true

require "hermes_agent/client/entity"

module HermesAgent
  class Client
    module Entities
      ##
      # A model advertised by the server (one entry of the `GET /v1/models`
      # list). Field readers are best-effort; {#to_h} remains the source of
      # truth.
      #
      # The `permission` field is intentionally not exposed as a reader: it was
      # observed empty, its element type is unknown (and likely a nested
      # object), so callers should reach it via {#[]} / {#to_h} for now.
      #
      class Model < Entity
        ##
        # The model identifier, e.g. `"hermes-test"`.
        # @return [String, nil]
        #
        def id
          self["id"]
        end

        ##
        # The object type, `"model"`.
        # @return [String, nil]
        #
        def object
          self["object"]
        end

        ##
        # When the model was created, as a Unix timestamp (seconds).
        # @return [Integer, nil]
        #
        def created
          self["created"]
        end

        ##
        # The organization that owns the model, e.g. `"hermes"`.
        # @return [String, nil]
        #
        def owned_by
          self["owned_by"]
        end

        ##
        # The root model id this model derives from.
        # @return [String, nil]
        #
        def root
          self["root"]
        end

        ##
        # The parent model id, or `nil` when there is no parent.
        # @return [String, nil]
        #
        def parent
          self["parent"]
        end
      end
    end
  end
end
