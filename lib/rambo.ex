defmodule Rambo do

  defstruct status: nil, out: "", err: ""

  @type t :: %__MODULE__{
          status: integer(),
          out: String.t(),
          err: String.t()
        }
  @type args :: String.t() | [iodata()] | nil
  @type result :: {:ok, t()} | {:error, t() | String.t()} | {:killed, t()}

  # TODO support kill

  @spec run(command :: String.t() | result(), args_or_opts :: args() | Keyword.t()) :: result()
  def run(command, args_or_opts) do
    case command do
      {:ok, %{status: 0, out: out}} ->
        command = args_or_opts
        run(command, in: out)

      {:error, reason} ->
        {:error, reason}

      command ->
        if Keyword.keyword?(args_or_opts) do
          run(command, nil, args_or_opts)
        else
          run(command, args_or_opts, [])
        end
    end
  end

  @spec run(command :: String.t() | result(), args :: args(), opts :: Keyword.t()) :: result()
  def run(command, args, opts) do
    case command do
      {:ok, %{out: out}} ->
        command = args
        args_or_opts = opts

        if Keyword.keyword?(args_or_opts) do
          run(command, nil, [in: out] ++ args_or_opts)
        else
          run(command, args_or_opts, in: out)
        end

      {:error, reason} ->
        {:error, reason}

      command when byte_size(command) > 0 ->
        {stdin, opts} = Keyword.pop(opts, :in)
        {envs, opts} = Keyword.pop(opts, :env, [])
        {current_dir, opts} = Keyword.pop(opts, :cd)
        {log, opts} = Keyword.pop(opts, :log, :stderr)
        # TODO implement timeout
        {_timeout, _opts} = Keyword.pop(opts, :timeout)

        log =
          case log do
            log when is_function(log) -> log
            true -> [:stdout, :stderr]
            log -> [log]
          end

        in_flags =
          [
            {:env, envs}
          ]
          |> put_flag_if(:stdin, stdin != nil)
          |> put_flag_if({:cd, current_dir}, current_dir != nil)


        command = List.to_string(:os.find_executable(String.to_charlist(command)))

        task = Task.async(fn ->
          {:ok, pid, _os_pid} = :exec.run([command | args], [:stdout, :stderr, :monitor | in_flags])

          if stdin != nil do
            :exec.send(pid, stdin)
            :exec.send(pid, :eof)
          end

          acc = receive_rec(%{
            stdout: [],
            stderr: [],
            status: nil
          }, log)

          stdout =
            acc.stdout
            |> Enum.reverse()
            |> :erlang.iolist_to_binary()

          stderr =
            acc.stderr
            |> Enum.reverse()
            |> :erlang.iolist_to_binary()

          out = %__MODULE__{
            out: stdout,
            err: stderr,
            status: acc.status
          }
          {:ok, out}
        end)

        Task.await(task)

      command ->
        raise ArgumentError, message: "invalid command '#{inspect(command)}'"
    end
  end

  def receive_rec(acc, log) do
    receive do
      {:stdout, _pid, data} ->
        maybe_log(:stdout, data, log)
        acc = update_in(acc.stdout, &[data | &1])
        receive_rec(acc, log)

      {:stderr, _pid, data} ->
        maybe_log(:stderr, data, log)
        acc = update_in(acc.stderr, &[data | &1])
        receive_rec(acc, log)

      {:DOWN, _, :process, _pid, :normal} ->
        %{acc | status: 0}

      {:DOWN, _, :process, _pid, {:exit_status, status}} ->
        %{acc | status: status}
    end
  end

  defp put_flag_if(flags, flag, true) do
    [flag | flags]
  end
  defp put_flag_if(flags, _flag, false) do
    flags
  end

  defp maybe_log(to, output, log) do
    if to in log do
      device =
        case to do
          :stdout -> :stdio
          :stderr -> :stderr
        end

      IO.binwrite(device, output)
    end
  end

end
