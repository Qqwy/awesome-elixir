
# This script will check if the readme markdown file contains valid formatting.

require Logger

defmodule Awesome.Order do
    def check_string_list_in_order([first, second | tail]) do
        case String.downcase(first) < String.downcase(second) do
            false -> throw "Words not in order #{inspect first} and #{inspect second}"
            true -> check_string_list_in_order([second] ++ tail)
        end
    end

    def check_string_list_in_order([_one]) do
        :true
    end

    def check_string_list_in_order([]) do
        :true
    end
end


defmodule Awesome do

    import Awesome.Order

    defp debug(message) do
        IO.puts "[debug] #{message}"
    end

    # Entry point
    def test_file(file) do

        http = Http.start(20)


        lines = File.read!(file)
        debug "Using Earmark to parse to data structure we can work with."
        { blocks, _links } = Earmark.Parser.parse(String.split(lines, ~r{\r\n?|\n}))

        debug "Ensure that there is a header at first."
        [%Earmark.Block.Heading{} | blocks] = blocks

        debug "Ensure that there is a introduction."
        [_introduction | blocks] = blocks

        debug "Ensure that there is a table of content list."
        [%Earmark.Block.List{blocks: tableOfContent} | blocksList ] = blocks

        debug "Parse table of content to list of categories."
        [%Earmark.Block.ListItem{blocks: [%Earmark.Block.Para{} | categories]} | tableOfContent ] = tableOfContent
        [%Earmark.Block.List{blocks: categories}] = categories
        categories = for %Earmark.Block.ListItem{blocks: [%Earmark.Block.Para{lines: [name]}]} <- categories do
            {title, _link} = parse_markdown_link(name)
            title
        end
        #IO.inspect categories

        debug "Parse table of content to list of resources."
        [%Earmark.Block.ListItem{blocks: [%Earmark.Block.Para{} | resources]} | _tableOfContent ] = tableOfContent
        [%Earmark.Block.List{blocks: resources}] = resources
        resources = for %Earmark.Block.ListItem{blocks: [%Earmark.Block.Para{lines: [name]}]} <- resources do
            {title, _link} = parse_markdown_link(name)
            title
        end
        #IO.inspect resources

        IO.puts "--------- START"
        # Parse the main content
        iterate_content(blocksList)

        debug "Collect all headings."
        headings = collect_headings(blocksList, [], [])
        #IO.inspect headings

        debug "Ensure headings are in alphabetic order."
        for list <- headings, do: check_string_list_in_order(list)
        debug "Ensure Headings are equal to the once in the tableOfContent."
        [^categories, ^resources] = headings;

        debug "Ensure entries are in alphabetic order."
        for block <- blocksList do
            sorted_entries block
        end

        debug "Waiting for all the HTTP requests to finish ..."

        responses = Task.await(http, 300000)
        notOk = responses |> Enum.filter(fn({statuscode, _url}) -> not (statuscode in [200, 301, 302]) end)
        case notOk do
            [] ->
                debug "No invalid links found"
            invalidLinks ->
                debug "INVALID links found:"
                IO.inspect invalidLinks
        end
    end

    def parse_markdown_link(string) do
        [^string, title, link] = Regex.run ~r/\[(.+)\]\((.+)\)/, string
        {title, link}
    end

    #-----

    def sorted_entries(%Earmark.Block.List{blocks: entriesList}) do
        # Filter down to single lines
        entries = Enum.map(entriesList, fn %Earmark.Block.ListItem{blocks: [ %Earmark.Block.Para{lines: [ line ]} ]} -> line end)
        names = Enum.map(entries, fn line ->
            line = line |> String.strip(?~)
            [^line, name | _rest] = Regex.run ~r/\[([^]]+)\]\(([^)]+)\) - (.+)./, line
            name
        end)
        check_string_list_in_order(names)
    end

    def sorted_entries(_) do

    end

    #-----

    def collect_headings([ %Earmark.Block.Heading{content: heading, level: 2} | tail], found_headings, all_headings) do
        collect_headings(tail, found_headings ++ [heading], all_headings)
    end

    def collect_headings([ %Earmark.Block.Heading{content: _heading, level: 1} | tail], found_headings, all_headings) do
        check_string_list_in_order(found_headings)
        collect_headings(tail, [], all_headings ++ [found_headings])
    end

    def collect_headings([_head | tail], found_headings, all_headings) do
        collect_headings(tail, found_headings, all_headings)
    end

    def collect_headings([], _found_headings, all_headings) do
        all_headings
    end

    #-----

    def iterate_content([]) do
        IO.puts "--------- END"
    end

    # Find a level 2 headline, followed by a paragraph and the list of links.
    def iterate_content([
        %Earmark.Block.Heading{content: heading, level: 2},
        %Earmark.Block.Para{lines: _lines},
        %Earmark.Block.List{blocks: blocks, type: :ul} | tail]) do
        IO.puts "-- #{heading}"
        check_list(blocks)
        iterate_content(tail)
    end

    # Find a level 1 headline followed by a paragraph.
    def iterate_content([
        %Earmark.Block.Heading{content: heading, level: 1},
        %Earmark.Block.Para{lines: _lines} | tail]) do
        IO.puts "- #{heading}"
        iterate_content(tail)
    end

    # Error handler, when not matching.
    def iterate_content([ head| tail]) do
        IO.puts "\n\tERROR: Could not match on:"
        IO.inspect head
        iterate_content(tail)
    end

    # Iterate through all
    def check_list(list) do
        for listItem <- list, do: validate_list_item(listItem)
    end

    # Validate that the link as listitem is valid formatted.
    def validate_list_item(%Earmark.Block.ListItem{blocks: [%Earmark.Block.Para{lines: [line]}], type: :ul}) do
        line = String.rstrip(line)
        if String.starts_with?(line, "~~") and String.ends_with?(line, "~~") do
            line = line |> String.strip(?~)
        end
        [^line, name, link, description] = Regex.run ~r/\[([^]]+)\]\(([^)]+)\) - (.+)\./, line
        IO.puts "\t'#{name}' #{link} '#{description}'"
        request_http_url(link)
    end

    def request_http_url(url) do
        #IO.inspect is_binary  url
        #IO.inspect url
        send(:http, {:get, url})
        #Awesome.Http.request(42, url)
        #IO.puts "Testing URL #{url}...\n"
        #case HTTPoison.get(url) do
        #  response = %HTTPoison.Response{status_code: 200} -> {:ok, response}
        #  response -> throw "HTTP Request failed #{inspect response}"
        #end
    end
end

Awesome.test_file("../README.md")
