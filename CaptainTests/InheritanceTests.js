Object.prototype.extends = function(superclass) {
    // Copy all functions from 'superclass' into 'this'
    for (var name in superclass) {
        if (typeof superclass[name] == "function")
            this[name] = superclass[name];
    }
    
    // And set the prototype
    this.prototype = superclass;
};


// We're defining two modules here - 'MainModule', and 'SubModule' (which inherits SubModule)

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

