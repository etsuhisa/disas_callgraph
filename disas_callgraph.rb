=begin

	Linuxのobjdumpを使ってディスアセンブルした結果から関数のコールグラフを作成します。
	ディスアセンブルの結果は「モジュール名.txt」で用意してください。

	$ for i in *; do echo $i; objdump -d -C $i > $i.txt; done
	$ ruby disas_callgraph.rb

	出力されたdisas_callgraph.htmlを開くと生成された関数がツリー表示されます。

=end
require 'json'
require 'set'

# ==============================================================================
# コールグラフ表示用 HTMLテンプレート
# ==============================================================================

# HTML前半部分のテンプレート
HTML_TEMPLATE_FRONT = <<~EOS
	<!DOCTYPE html>
	<html>
	<head>
	<title>コールグラフ</title>
	<style>
		body {
			font-family: sans-serif;
		}
		ul {
			list-style-type: none;
			padding-left: 20px;
		}
		li {
			cursor: pointer;
			margin-bottom: 2px;
		}
		li:hover {
			color: blue;
		}
		.collapsed > ul {
			display: none;
		}
		.arrow {
			display: inline-block;
			width: 0;
			height: 0;
			border-top: 4px solid transparent;
			border-bottom: 4px solid transparent;
			border-left: 6px solid black;
			margin-right: 5px;
			transition: transform 0.1s ease-in-out;
		}
		.collapsed > .arrow {
			transform: rotate(0deg);
		}
		.expanded > .arrow {
			transform: rotate(90deg);
		}
	</style>
	</head>
	<body>

	<div>
		<h1>関数コールグラフ</h1>
		<p>トップレベルの関数をここに記載した文字列でフィルタすることができます。</p>
		<input type="text" id="top_filter_input" placeholder="関数名でフィルタ">
		<button id="filter_button">フィルタ</button>
		<div style="margin-top: 10px;">
			<label><input type="radio" name="call_direction" value="callees" checked> 呼び出し先ツリー</label>
			<label><input type="radio" name="call_direction" value="callers"> 呼び出し元ツリー</label>
		</div>
		<ul id="callgraph">
		</ul>
	</div>

	<script>
	const funcs = 
EOS

# HTML後半部分のテンプレート
HTML_TEMPLATE_BACK = <<~EOS
	;

	document.addEventListener('DOMContentLoaded', () => {
		const callgraphContainer = document.getElementById('callgraph');
		const topFilterInput = document.getElementById('top_filter_input');
		const filterButton = document.getElementById('filter_button');
		const callDirectionRadios = document.querySelectorAll('input[name="call_direction"]');

		let currentDirection = 'callees';

		function createFunctionListItem(funcName) {
			const li = document.createElement('li');
			const arrow = document.createElement('span');
			arrow.classList.add('arrow');
			arrow.style.visibility = 'hidden'; // デフォルトでは非表示

			li.appendChild(arrow);

			const funcText = document.createTextNode(`${funcName} (${funcs.mod[funcName] || 'unknown'})`);
			li.appendChild(funcText);
			li.dataset.functionName = funcName;

			li.addEventListener('click', handleFunctionClick);

			return li;
		}

		function handleFunctionClick(event) {
			event.stopPropagation(); // 親要素へのクリックイベントの伝播を防ぐ

			const li = event.currentTarget;
			const funcName = li.dataset.functionName;

			let subUl = li.querySelector('ul');
			const arrow = li.querySelector('.arrow');

			// 子要素（subUl）が既に存在する場合
			if (subUl) {
				// クラスをトグルして表示/非表示を切り替える
				li.classList.toggle('collapsed');
				li.classList.toggle('expanded');
			}
			// 子要素がまだロードされていない場合
			else {
				// currentDirection に応じて、funcs.callers または funcs.callees からデータを取得
				const relatedFunctions = funcs[currentDirection][funcName];

				if (relatedFunctions && relatedFunctions.length > 0) {
					subUl = document.createElement('ul');
					relatedFunctions.sort().forEach(relatedFunc => {
						// 既にロードされた子要素はクリック可能にする必要がないため、
						// 子要素のアイテムにはイベントリスナーを付けないか、伝播を考慮する。
						// ここでは親要素のイベントリスナーが各LIに設定されているため、
						// 再帰的にクリック可能になる。
						const calledLi = createFunctionListItem(relatedFunc);
						subUl.appendChild(calledLi);
					});
					li.appendChild(subUl);

					// 初回ロード時に collapsed クラスを削除し、expanded を追加する
					li.classList.remove('collapsed');
					li.classList.add('expanded');

					arrow.style.visibility = 'visible'; // 子要素があれば矢印を表示
				} else {
					// 子要素がない場合は矢印を非表示にする
					arrow.style.visibility = 'hidden';
					// collapsed/expanded クラスの状態もリセット（念のため）
					li.classList.remove('collapsed', 'expanded');
				}
			}
		}

		function renderFunctions(filterText = '') {
			callgraphContainer.innerHTML = '';
			const sortedFuncNames = Object.keys(funcs.mod).sort();
			const lowerCaseFilterText = filterText.toLowerCase();

			sortedFuncNames.forEach(funcName => {
				if (funcName.toLowerCase().includes(lowerCaseFilterText)) {
					const li = createFunctionListItem(funcName);

					// 子要素が存在するかどうかで初期の矢印の表示を決定
					// currentDirection に応じた子要素が一つでもあれば矢印を表示
					const relatedFunctions = funcs[currentDirection][funcName];
					if (relatedFunctions && relatedFunctions.length > 0) {
						li.querySelector('.arrow').style.visibility = 'visible';
					} else {
						li.querySelector('.arrow').style.visibility = 'hidden';
					}

					li.classList.add('collapsed'); // 最初は畳まれた状態
					callgraphContainer.appendChild(li);
				}
			});
		}

		// 初期描画
		renderFunctions();

		// フィルタボタンのイベントリスナー
		filterButton.addEventListener('click', () => {
			const filterText = topFilterInput.value.trim();
			renderFunctions(filterText);
		});

		// Enterキーでのフィルタリング
		topFilterInput.addEventListener('keypress', (event) => {
			if (event.key === 'Enter') {
				filterButton.click();
			}
		});

		// ラジオボタンの変更イベントリスナー
		callDirectionRadios.forEach(radio => {
			radio.addEventListener('change', (event) => {
				currentDirection = event.target.value;
				renderFunctions(topFilterInput.value.trim()); // フィルタを維持して再描画
			});
		});
	});
	</script>
	</body>
	</html>
EOS

# ==============================================================================
# メイン処理ロジック
# ==============================================================================

# パフォーマンス最適化のための正規表現の事前コンパイル
# 関数定義のパターンにマッチ（例: 0000000000401120 <_foo>:）
FUNCTION_DEF_REGEX = /^\h+\s+<([^>@]+)(@plt)?>:/
# 関数呼び出し（call命令）のパターンにマッチ（例: callq  0x401030 <_printf@plt>）
CALL_INSN_REGEX = /\tcall\w*\s+\h+\s+<([^>@]+)(@plt)?>/

# プログラム構造を保持するハッシュを初期化（解析時の重複確認を高速化するため Set を使用）
# :callees はその関数が呼び出す関数（呼び出し先）のリスト
# :callers はその関数を呼び出す関数（呼び出し元）のリスト
# :mod     はその関数が属するモジュール（ファイル名）
call_graph = {
	callees: Hash.new { |h, k| h[k] = Set.new },
	callers: Hash.new { |h, k| h[k] = Set.new },
	mod: {}
}

current_function = nil

# ディスアセンブルされたテキストファイル（*.txt）を順番に解析
Dir.glob("*.txt") do |filename|
	# ファイル名から拡張子を除いた部分をモジュール名とする
	module_name = filename.sub(/\.txt$/, "")

	File.foreach(filename) do |line|
		case line
		when FUNCTION_DEF_REGEX
			# `@plt` サフィックスがある場合はPLTエントリ（動的リンク用）のためスキップ
			next if $2 && !$2.empty?

			current_function = $1
			# `main` 関数の場合は、モジュール名を付与して区別できるようにする
			current_function = "main##{module_name}" if current_function == "main"

			# 関数がどのモジュールに属しているかを登録
			call_graph[:mod][current_function] = module_name

		when CALL_INSN_REGEX
			# 現在解析中の関数がない場合はスキップ
			next unless current_function

			called_function = $1

			# Set を使って重複を排除しながら、呼び出し・被呼び出しの関係を記録
			call_graph[:callees][current_function] << called_function
			call_graph[:callers][called_function] << current_function
		end
	end
end

# きれいな JSON を生成するため、Set からソート済みの配列に変換
formatted_data = {
	callees: call_graph[:callees].transform_values { |set| set.to_a.sort }.sort.to_h,
	callers: call_graph[:callers].transform_values { |set| set.to_a.sort }.sort.to_h,
	mod: call_graph[:mod].sort.to_h
}

# 最終的な結果を HTML ファイルとして出力（JavaScript のデータ構造を埋め込む）
File.open("callgraph.html", "w") do |file|
	file.puts HTML_TEMPLATE_FRONT
	file.puts JSON.pretty_generate(formatted_data)
	file.puts HTML_TEMPLATE_BACK
end
