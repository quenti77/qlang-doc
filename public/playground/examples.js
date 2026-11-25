export const EXAMPLES = [
  {
    name: 'Bonjour',
    code: `let name = "monde"
print("Bonjour {name} !")

for i in 1..4 do
    print("ligne {i}")
end
`,
  },
  {
    name: 'Structures et méthodes',
    code: `struct Point
    public x: int
    public y: int
end

impl Point
    public fun manhattan(self) -> int
        self.x.abs() + self.y.abs()
    end
end

let p = Point { x: 3, y: -4 }
print("distance : {p.manhattan()}")
`,
  },
  {
    name: 'Result et match',
    code: `fun diviser(a: int, b: int) -> Result<int, string>
    if b == 0 then
        return Err("division par zéro")
    end
    Ok(a // b)
end

for b in [2, 0] do
    match diviser(10, b)
        case Ok(v) then print("10 / {b} = {v}")
        case Err(e) then print("erreur : {e}")
    end
end
`,
  },
  {
    name: 'Tableaux et dictionnaires',
    code: `let notes = [12, 8, 15, 9]
let moyenne = notes.sum() / notes.len()
print("moyenne : {moyenne}")

let ages: map<string, int> = { "Ana": 31, "Bob": 27 }
for nom in ages.keys() do
    print("{nom} a {ages[nom]} ans")
end
`,
  },
  {
    name: 'Lire une saisie',
    code: `print("Comment t'appelles-tu ?")
let nom = read()
print("Salut {nom} !")
`,
  },
];
