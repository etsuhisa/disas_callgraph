=begin

	Linuxのobjdumpを使ってディスアセンブルした結果から関数のコールグラフを作成します。

	$ for i in *; do echo $i; objdump -d -C $i > $i.txt; done
	$ ruby disas_callgraph.rb

	出力されたdisas_callgraph.htmlを開くと生成された関数がツリー表示されます。

=end
tmpl1 = <<EOS
<!DOCTYPE html>
<html>
<head>
<title>Callgraph</title>
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
	<h1>Function Call Graph</h1>
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

tmpl2 = <<EOS
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
		} else {
			// 子要素がまだロードされていない場合
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

# プログラム構造を保持するハッシュを初期化。
# :callees はその関数が呼び出す関数（呼び出し先）のリスト
# :callers はその関数を呼び出す関数（呼び出し元）のリスト
# :mod は関数が属するモジュール
funcs = {:callees => {}, :callers => {}, :mod => {}}
func = nil # 現在処理中の関数名

Dir::glob("*.txt") do |file|
	mod = file.sub(/\.txt/, "") # ファイル名から拡張子を除いたものをモジュール名とする
	File::foreach(file) do |line|
		case line
		# 関数定義の行を検出 (例: 0000000000401120 <_foo>:)
		when /^\h+ \<([^\>@]+)(@plt)?\>:/
			# @plt サフィックスがない場合のみ関数名を設定（PLT エントリは対象外）
			func = $1 if $2.nil? || $2.empty?
			# 'main' 関数はモジュール名を付加して区別
			func = "main##{mod}" if func == "main"
			
			# 新しい関数が見つかった場合、データ構造を初期化
			funcs[:mod][func] = mod # 関数のモジュール名を記録
			funcs[:callees][func] = [] unless funcs[:callees].key?(func) # 呼び出し先のリストを初期化
			funcs[:callers][func] = [] unless funcs[:callers].key?(func) # 呼び出し元のリストを初期化
			
		# call 命令の行を検出 (例:     callq  0x401030 <_printf@plt>)
		when /\tcallw*\s+\h+\s+<([^>@]+)(@plt)?>/
			called_func = $1 # 現在の関数 (func) が呼び出す先の関数名
			
			# 現在の関数 (func) の呼び出し先リスト (:callees) に called_func を追加
			# func が nil の場合（関数定義が見つからないまま call が検出された場合）はスキップ
			if func && !funcs[:callees][func].include?(called_func)
				funcs[:callees][func] << called_func
			end
			
			# called_func を呼び出している関数リスト (:callers) に func を追加
			# called_func のエントリが存在しない場合は先に初期化
			funcs[:callers][called_func] = [] unless funcs[:callers].key?(called_func)
			if func && !funcs[:callers][called_func].include?(func)
				funcs[:callers][called_func] << func
			end
		end
	end
end

# 生成される HTML ファイルに JavaScript のデータ構造を書き込む
File::open("callgraph.html", "w") do |f|
	f.puts tmpl1
	f.puts "{"
	
	f.puts "\tcallees: {" # この関数が呼び出す関数 (Callees)
	funcs[:callees].keys.sort.each do |func_name|
		f.printf(%Q##\t\t"%s": [\n#, func_name)
		# ユニーク化してソートした呼び出し先関数名を書き出す
		funcs[:callees][func_name].uniq.sort.each do |callee_name|
			f.printf(%Q[\t\t\t"%s",\n], callee_name)
		end
		f.puts "\t\t],"
	end
	f.puts "\t},"

	f.puts "\tcallers: {" # この関数を呼び出している関数 (Callers)
	funcs[:callers].keys.sort.each do |func_name|
		f.printf(%Q#\t\t"%s": [\n#, func_name)
		# ユニーク化してソートした呼び出し元関数名を書き出す
		funcs[:callers][func_name].uniq.sort.each do |caller_name|
			f.printf(%Q[\t\t\t"%s",\n], caller_name)
		end
		f.puts "\t\t],"
	end
	f.puts "\t},"

	f.puts "\tmod: {" # 関数のモジュール情報
	funcs[:mod].keys.sort.each do |func_name|
		mod = funcs[:mod][func_name]
		f.printf(%Q[\t\t"%s": "%s",\n], func_name, mod)
	end
	f.puts "\t}"
	f.puts "}"
	f.puts tmpl2
end
