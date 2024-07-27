require "http/server"
require "http/web_socket"

module Scaffold
  VERSION = "0.1.0"

  annotation Get; end
  annotation Post; end
  annotation Patch; end
  annotation Put; end
  annotation Delete; end
  annotation Head; end
  annotation Options; end
  annotation All; end
  annotation Upgrade; end

  alias Response = HTTP::Server::Response

  private class Redirect < Exception
    getter status : HTTP::Status
    getter url : String | URI

    def initialize(@status : HTTP::Status, @url : String | URI)
    end
  end

  abstract class Controller
    include HTTP::Handler

    macro inherited
      private SCROUTES = {} of String => Hash(String, {String, Int32, Bool})
      private SCHANDLE = {} of Symbol => Int32

      macro method_added(method)
        \{% count = method.args.size %}
        {% for name in %i[Get Post Patch Put Delete Head Options All] %}
          \{%
            if anno = method.annotation(::SC::{{ name.id }})
              route = anno.args[0]

              unless route.class_name == "StringLiteral" || route.class_name == "RegexLiteral"
                anno.raise "route argument must be a string literal or regex literal"
              end

              verb = anno.name.names.last.upcase.stringify
              if SCROUTES[route] && SCROUTES[route][verb]
                anno.raise "a route already exists with this method"
              end

              upgrade = false
              if anno = method.annotation(::SC::Upgrade)
                if anno.args.size == 0 || anno.args.size > 1
                  anno.raise "expected one argument for Upgrade annotation"
                elsif anno.args[0] != :websocket
                  anno.raise "only 'websocket' is currently supported for Upgrade annotation"
                end

                unless count == 2
                  method.raise "websocket route methods can only accept a websocket and context as arguments"
                end

                if method.args[0].restriction
                  type = method.args[0].restriction.resolve
                  unless type <= ::HTTP::WebSocket
                    type.raise "expected argument #1 to be HTTP::WebSocket, not #{type}"
                  end
                end

                if method.args[1].restriction
                  type = method.args[1].restriction.resolve
                  unless type <= ::HTTP::Server::Context
                    type.raise "expected argument #2 to be HTTP::Server::Context, not #{type}"
                  end
                end

                upgrade = true
              else
                if count > 2
                  type.raise "wrong number of arguments for route method (given #{count}, expected 0..2)"
                end

                if count == 1 && method.args[0].restriction
                  type = method.args[0].restriction.resolve
                  if type <= ::HTTP::Request
                    count = -1
                  elsif type <= ::HTTP::Server::Response
                    count = -2
                  else
                    method.raise "expected argument #1 to be HTTP::Request or HTTP::Server::Response, not #{type}"
                  end
                end
              end

              unless SCROUTES[route]
                SCROUTES[route] = {} of String => {String, Int32, Bool}
              end
              SCROUTES[route][verb] = {method.name, count, upgrade}
            end
          %}
        {% end %}
        {% for name in %i[on_not_found on_method_not_allowed] %}
          \{%
            if method.name == {{ name.stringify }} && method.annotations.empty?
              if count > 2
                method.raise "wrong number of arguments for handler method (given #{count}, expected 0..2)"
              end

              if count == 1 && method.args[0].restriction
                type = method.args[0].restriction.resolve
                if type <= ::HTTP::Request
                  count = -1
                elsif type <= ::HTTP::Server::Response
                  count = -2
                else
                  method.raise "expected argument #1 to be HTTP::Request or HTTP::Server::Response, not #{type}"
                end
              end

              SCHANDLE[{{ name }}] = count
            end
          %}
        {% end %}
        {% for name, type in {on_incoming: ::HTTP::Request, on_outgoing: ::HTTP::Server::Response} %}
          \{%
            if method.name == {{ name.stringify }} && method.annotations.empty?
              unless count == 1
                method.raise "wrong number of arguments for handler method (given #{count}, expected 1)"
              end

              if method.args[0].restriction
                type = method.args[0].restriction.resolve
                unless type <= {{ type }}
                  method.raise "expected argument #1 to be {{ type }}, not #{type}"
                end
              end

              SCHANDLE[:{{ name }}] = 0
            end
          %}
        {% end %}
      end

      macro finished
        def call(context : ::HTTP::Server::Context) : ::Nil
          \{% if SCHANDLE[:on_incoming] %}
            on_incoming context.request
          \{% end %}

          case context.request.path
          \{% for route, method in SCROUTES %}
          when \{{ route }}
            \{% if info = method["ALL"] %}
              \{% if info[2] %}
                handler = ::HTTP::WebSocketHandler.new &->\{{ info[0] }}(::HTTP::WebSocket, ::HTTP::Server::Context)
                handler.call context
              \{% else %}
                \{% if info[1] == 0 %}
                  transform context.response, \{{ info[0] }}
                \{% elsif info[1] == -1 || info[1] == 1 %}
                  transform context.response, \{{ info[0] }}(context.request)
                \{% elsif info[1] == -2 %}
                  transform context.response, \{{ info[0] }}(context.response)
                \{% else %}
                  transform context.response, \{{ info[0] }}(context.request, context.response)
                \{% end %}
              \{% end %}
            \{% else %}
              case context.request.method
              \{% for verb, info in method %}
              when \{{ verb }}
                \{% if info[2] %}
                  handler = ::HTTP::WebSocketHandler.new &->\{{ info[0] }}(::HTTP::WebSocket, ::HTTP::Server::Context)
                  handler.call context
                \{% else %}
                  \{% if info[1] == 0 %}
                    transform context.response, \{{ info[0] }}
                  \{% elsif info[1] == -1 || info[1] == 1 %}
                    transform context.response, \{{ info[0] }}(context.request)
                  \{% elsif info[1] == -2 %}
                    transform context.response, \{{ info[0] }}(context.response)
                  \{% else %}
                    transform context.response, \{{ info[0] }}(context.request, context.response)
                  \{% end %}
                \{% end %}
              \{% end %}
              else
                \{% if count = SCHANDLE[:on_method_not_allowed] %}
                  \{% if count == 0 %}
                    transform context.response, on_method_not_allowed
                  \{% elsif count == -1 || count == 1 %}
                    transform context.response, on_method_not_allowed(context.request)
                  \{% elsif count == -2 %}
                    transform context.response, on_method_not_allowed(context.response)
                  \{% else %}
                    transform context.response, on_method_not_allowed(context.request, context.response)
                  \{% end %}
                \{% else %}
                  context.response.tap do |res|
                    res.status = :method_not_allowed
                    res.headers["Allow"] = \{{ method.keys.join "," }}
                  end
                \{% end %}
              end
            \{% end %}
          \{% end %}
          else
            \{% if count = SCHANDLE[:on_not_found] %}
              \{% if count == 0 %}
                transform context.response, on_not_found
              \{% elsif count == -1 || count == 1 %}
                transform context.response, on_not_found(context.request)
              \{% elsif count == -2 %}
                transform context.response, on_not_found(context.response)
              \{% else %}
                transform context.response, on_not_found(context.request, context.response)
              \{% end %}
            \{% else %}
              call_next context
            \{% end %}
          end

          \{% if SCHANDLE[:on_outgoing] %}
            on_outgoing context.response
          \{% end %}
        rescue ex
          transform context.response, ex
        end
      end
    end

    def redirect(to url : String | URI, status : HTTP::Status = :found) : Nil
      raise Redirect.new status, url
    end

    def transform(res : Response, value : String) : Nil
      res << value
    end

    def transform(res : Response, value : Response) : Nil
    end

    def transform(res : Response, value : Nil) : Nil
      res.status = :no_content
    end

    def transform(res : Response, value : Redirect) : Nil
      res.redirect value.url.to_s, value.status
    end

    def transform(res : Response, value : Exception) : Nil
      res.status = :internal_server_error
      res << "An unexpected exception occurred:\n"
      value.inspect_with_backtrace res
    end

    def transform(res : Response, value : T) : NoReturn forall T
      {% T.raise "no transform method defined for type #{T}" %}
    end
  end
end

alias SC = Scaffold
