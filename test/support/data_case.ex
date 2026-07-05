defmodule Notex.DataCase do
  @moduledoc """
  Test setup for file-backed Notex storage.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Notex.DataCase
    end
  end

  setup do
    old_storage_root = Application.get_env(:notex, :storage_root)

    storage_root =
      Path.join(System.tmp_dir!(), "notex-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(storage_root)
    Application.put_env(:notex, :storage_root, storage_root)

    on_exit(fn ->
      if old_storage_root do
        Application.put_env(:notex, :storage_root, old_storage_root)
      else
        Application.delete_env(:notex, :storage_root)
      end

      File.rm_rf(storage_root)
    end)

    :ok
  end

  def storage_root do
    Application.fetch_env!(:notex, :storage_root)
  end
end
