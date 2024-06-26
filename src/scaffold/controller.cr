module Scaffold
  abstract class Controller
    include HTTP::Handler

    macro inherited
      macro finished
        \{% routes = {} of String => Def %}
        \{% for method in @type.methods %}
          \{% anno = method.annotation(SC::Get) || method.annotation(SC::Post) %}
          \{% if anno %}
            \{% anno.raise "no route argument specified in annotation" if anno.args.empty? %}
            \{% anno.raise "route argument must be a string literal" unless anno.args[0] == StringLiteral %}
            \{% routes[anno[0]] = method %}
          \{% end %}
        \{% end %}
        \{% p @type.methods %}
        def handle_incoming(req : ::HTTP::Request, res : ::HTTP::Server::Response) : ::Nil
          case parse_route(req.path)
          \{% for route, method in routes %}
          when \{{ route }}
            \{% if method.args.empty? %}
              transform \{{ method.name }}, res
            \{% elsif method.args.size == 1 %}
              transform \{{ method.name }}(req), res
            \{% else %}
              \{% method.raise "expected one argument for route method; got #{method.args.size}" %}
            \{% end %}
          \{% end %}
          else
            raise "route not found"
          end
        rescue ex
          transform ex, res
        end
      end
    end

    protected def parse_route(route : String) : String | Regex
      route # TODO
    end

    def call(context : HTTP::Server::Context)
      handle_incoming context.request, context.response
    end

    def transform(value : String, res : Response) : Nil
      res << value
    end

    def transform(value : Response, res : Response) : Nil
    end

    def transform(value : Exception, res : Response) : Nil
      res.status = :internal_server_error
      res << "An unexpected exception occurred:" << value << '\n'
    end

    def transform(value : T, res : Response) : NoReturn forall T
      {% T.raise "no transformer method defined for type #{T}" %}
    end
  end
end
