defmodule Nifsy.Stream do
  @moduledoc false

  alias Nifsy.Native

  defstruct [options: nil, path: nil, line_or_bytes: :line]
  @opaque t :: %__MODULE__{
    options: Nifsy.options,
    path: Path.t,
    line_or_bytes: :line | pos_integer
  }

  defimpl Collectable do
    def into(%{options: options, path: path} = stream) do
      case Nifsy.open(path, :write, options) do
        {:ok, handle} ->
          {:ok, into(handle.handle, stream)}

        {:error, reason} ->
          raise "could not stream #{path}: #{inspect(reason)}"
      end
    end

    def into(handle, stream) do
      fn
        :ok, {:cont, x} ->
          Native.write(handle, x)

        :ok, :done ->
          :ok = Native.close(handle)
          stream

        :ok, :halt ->
          :ok = Native.close(handle)
      end
    end
  end

  defimpl Enumerable do
    def reduce(%{options: options, path: path, line_or_bytes: line_or_bytes}, acc, fun) do
      start_fun =
        fn ->
          case Nifsy.open(path, :read, options) do
            {:ok, handle} ->
              handle.handle

            {:error, reason} ->
              raise "could not stream #{path}: #{inspect(reason)}"
          end
        end

      next_fun = next_fun_gen(line_or_bytes)

      Stream.resource(start_fun, next_fun, &Native.close/1).(acc, fun)
    end

    def next_fun_gen(:line) do
      fn handle ->
        case Native.read_line(handle) do
          :eof -> {:halt, handle}
          {:ok, line} -> {[line], handle}
        end
      end
    end
    def next_fun_gen(bytes) when is_integer(bytes) do
      fn handle ->
        case Native.read(handle, bytes) do
          :eof -> {:halt, handle}
          {:ok, line} -> {[line], handle}
        end
      end
    end

    def count(_stream) do
      {:error, __MODULE__}
    end

    def member?(_stream, _term) do
      {:error, __MODULE__}
    end
  end
end
