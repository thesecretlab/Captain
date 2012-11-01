Object.prototype.extends = function(superclass) {
    for (var name in superclass) {
        this[name] = superclass[name];
    }
    this.prototype = superclass;
};

this.MainModule = {};

MainModule.doSomething = function() {
    return "Foo";
}
MainModule.doSomethingImpressive = function() {
    return "Yes";
}

this.SubModule = {};
SubModule.extends(MainModule);

SubModule.doSomething = function() {
    return this.prototype.doSomething() + "Bar, " + this.name;
}

SubModule.doSomething();
SubModule.doSomethingImpressive();

